#!/usr/bin/env python3
"""Fine-tune a Vietnamese SmolVLM2 LoRA adapter from image-grounded JSONL."""
import argparse
import json
from pathlib import Path

DEFAULT_MODEL = "HuggingFaceTB/SmolVLM2-500M-Video-Instruct"
TARGETS = {"q_proj", "k_proj", "v_proj", "o_proj"}


def load_rows(path: Path, image_root: Path):
    rows = []
    root = image_root.resolve()
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"line {line_number}: invalid JSON ({error.msg})") from None
        if not isinstance(row, dict):
            raise ValueError(f"line {line_number}: each JSONL row must be an object")
        image_value = row.get("image")
        if not isinstance(image_value, str) or not image_value.strip():
            raise ValueError(f"line {line_number}: image must be a non-empty relative path")
        image = (root / image_value).resolve()
        try:
            image.relative_to(root)
        except ValueError:
            raise ValueError(f"line {line_number}: image path escapes image root") from None
        messages = row.get("messages")
        if not image.is_file():
            raise ValueError(f"line {line_number}: missing image {image_value!r}")
        if (
            not isinstance(messages, list)
            or len(messages) != 2
            or any(not isinstance(message, dict) for message in messages)
        ):
            raise ValueError(f"line {line_number}: expected user and assistant messages")
        if [message.get("role") for message in messages] != ["user", "assistant"]:
            raise ValueError(f"line {line_number}: expected user then assistant")
        if any(not isinstance(message.get("content"), str) or not message["content"].strip() for message in messages):
            raise ValueError(f"line {line_number}: message content must be non-empty text")
        row["_image_path"] = str(image)
        rows.append(row)
    if not rows:
        raise ValueError(f"no training rows found in {path}")
    return rows


class ImageQaDataset:
    def __init__(self, rows, processor, torch):
        self.rows = rows
        self.processor = processor
        self.torch = torch

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, index):
        from PIL import Image

        row = self.rows[index]
        with Image.open(row["_image_path"]) as source:
            image = source.convert("RGB")
        user_message = {
            "role": "user",
            "content": [
                {"type": "image", "image": image},
                {"type": "text", "text": row["messages"][0]["content"]},
            ],
        }
        prompt = self.processor.apply_chat_template(
            [user_message], add_generation_prompt=True, tokenize=True,
            return_dict=True, return_tensors="pt",
        )
        full = self.processor.apply_chat_template(
            [user_message, {
                "role": "assistant",
                "content": [{"type": "text", "text": row["messages"][1]["content"]}],
            }],
            add_generation_prompt=False, tokenize=True, return_dict=True,
            return_tensors="pt",
        )
        labels = full["input_ids"].clone()
        labels[:, :prompt["input_ids"].shape[-1]] = -100
        pad_id = self.processor.tokenizer.pad_token_id
        image_id = getattr(self.processor, "image_token_id", None)
        if pad_id is not None:
            labels[labels == pad_id] = -100
        if image_id is not None:
            labels[labels == image_id] = -100
        full["labels"] = labels
        return full


def collate_one(example):
    # The variable-resolution image processor can emit different patch shapes;
    # batch size one avoids padding image tensors and keeps peak memory bounded.
    return example[0]


def attach_lora(model, config, LoraConfig, get_peft_model):
    target_modules = [
        name for name, _ in model.named_modules()
        if ".text_model." in name and name.rsplit(".", 1)[-1] in TARGETS
    ]
    if not target_modules:
        raise ValueError("could not find text_model q/k/v/o projections; inspect this checkpoint's module names")
    adapter_config = LoraConfig(
        r=int(config.get("rank", 8)),
        lora_alpha=int(config.get("alpha", 16)),
        lora_dropout=float(config.get("dropout", 0.05)),
        target_modules=target_modules,
        bias="none",
        task_type="CAUSAL_LM",
    )
    return get_peft_model(model, adapter_config), target_modules


def run_preflight(model_id, config, parser):
    try:
        import torch
        from peft import LoraConfig, get_peft_model
        from transformers import AutoModelForImageTextToText, AutoProcessor
    except ImportError as error:
        parser.error(f"training dependencies are missing ({error}); see requirements.txt")
    if not torch.cuda.is_available():
        parser.error("CUDA preflight requires a CUDA-enabled PyTorch build")

    processor = AutoProcessor.from_pretrained(model_id)
    model = AutoModelForImageTextToText.from_pretrained(
        model_id, dtype=torch.float16
    ).to("cuda")
    model.config.use_cache = False
    model, target_modules = attach_lora(model, config, LoraConfig, get_peft_model)
    model.print_trainable_parameters()
    print(json.dumps({
        "model": model_id,
        "device": torch.cuda.get_device_name(0),
        "processor": type(processor).__name__,
        "target_module_count": len(target_modules),
        "target_module_examples": target_modules[:8],
        "cuda_allocated_mb": round(torch.cuda.memory_allocated() / (1024 * 1024), 2),
    }, ensure_ascii=False, indent=2))


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(__file__).parent / "configs" / "lora.json")
    parser.add_argument("--train-jsonl", type=Path)
    parser.add_argument("--validation-jsonl", type=Path)
    parser.add_argument("--image-root", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("outputs/smolvlm2_vi_lora"))
    parser.add_argument("--print-plan", action="store_true")
    parser.add_argument("--validate-only", action="store_true", help="validate data paths/schema without loading a model")
    parser.add_argument("--preflight", action="store_true", help="load checkpoint and verify CUDA/LoRA injection without training data")
    parser.add_argument("--execute", action="store_true", help="start LoRA training")
    parser.add_argument("--max-steps", type=int, default=-1, help="optional bounded smoke run; -1 uses epochs")
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8")) if args.config.exists() else {}
    if config.get("vision_encoder") != "frozen" or config.get("vision_projection") != "frozen" or config.get("language_backbone") != "frozen":
        parser.error("first experiment freezes vision, projection, and base language weights")
    if set(config.get("lora_targets", [])) != TARGETS:
        parser.error("first experiment must target q_proj, k_proj, v_proj, and o_proj")
    model_id = config.get("base_checkpoint") or DEFAULT_MODEL

    if args.print_plan:
        print(json.dumps({**config, "base_checkpoint": model_id}, ensure_ascii=False, indent=2))
        print("Base checkpoint is the official Transformers model; Android .litertlm is inference-only.")
        if not args.execute and not args.validate_only and not args.preflight:
            return

    if not (args.validate_only or args.preflight or args.execute):
        parser.error("pass --print-plan, --validate-only, --preflight, or --execute")
    if args.preflight:
        run_preflight(model_id, config, parser)
        return
    if not args.train_jsonl or not args.image_root or (args.execute and not args.validation_jsonl):
        parser.error("--train-jsonl and --image-root are required; --validation-jsonl is also required for training")

    try:
        train_rows = load_rows(args.train_jsonl, args.image_root)
        validation_rows = load_rows(args.validation_jsonl, args.image_root) if args.validation_jsonl else []
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    train_images = {row["_image_path"] for row in train_rows}
    validation_images = {row["_image_path"] for row in validation_rows}
    overlap = train_images & validation_images
    if overlap:
        parser.error(f"training and validation splits share {len(overlap)} image(s)")
    print(f"Validated {len(train_rows)} training rows and {len(validation_rows)} validation rows.")
    if args.validate_only:
        return

    try:
        import torch
        from peft import LoraConfig, get_peft_model
        from transformers import AutoModelForImageTextToText, AutoProcessor, Trainer, TrainingArguments
    except ImportError as error:
        parser.error(f"training dependencies are missing ({error}); see requirements.txt")
    if not torch.cuda.is_available():
        parser.error("CUDA training is required; install a CUDA-enabled PyTorch build first")

    dtype = torch.float16  # P100 does not support bfloat16.
    processor = AutoProcessor.from_pretrained(model_id)
    model = AutoModelForImageTextToText.from_pretrained(model_id, dtype=dtype).cuda()
    model.config.use_cache = False
    model.gradient_checkpointing_enable()
    if hasattr(model, "enable_input_require_grads"):
        model.enable_input_require_grads()
    for parameter in model.parameters():
        parameter.requires_grad = False

    model, _ = attach_lora(model, config, LoraConfig, get_peft_model)
    model.print_trainable_parameters()
    train_data = ImageQaDataset(train_rows, processor, torch)
    validation_data = ImageQaDataset(validation_rows, processor, torch) if validation_rows else None
    train_args = TrainingArguments(
        output_dir=str(args.output_dir),
        num_train_epochs=float(config.get("epochs", 1)),
        max_steps=args.max_steps,
        per_device_train_batch_size=1,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=int(config.get("gradient_accumulation_steps", 8)),
        learning_rate=float(config.get("learning_rate", 1e-4)),
        fp16=True,
        gradient_checkpointing=True,
        eval_strategy="epoch" if validation_data else "no",
        save_strategy="epoch",
        save_total_limit=1,
        remove_unused_columns=False,
        dataloader_pin_memory=False,
        report_to="none",
    )
    trainer = Trainer(
        model=model,
        args=train_args,
        train_dataset=train_data,
        eval_dataset=validation_data,
        data_collator=collate_one,
    )
    trainer.train()
    trainer.save_model(str(args.output_dir))
    processor.save_pretrained(args.output_dir)
    print(f"Saved LoRA adapter and processor to {args.output_dir}")


if __name__ == "__main__":
    main()
