#!/usr/bin/env python3
"""Generate image-grounded predictions for a fixed Vietnamese VLM test split."""
import argparse
import json
import time
from pathlib import Path

from train_lora import DEFAULT_MODEL, load_rows


def load_test_rows(path: Path, image_root: Path):
    rows = load_rows(path, image_root)
    for index, row in enumerate(rows, 1):
        if not isinstance(row.get("sample_id"), str) or not row["sample_id"]:
            raise ValueError(f"line {index}: missing stable sample_id; prepare the dataset first")
        if not isinstance(row.get("task"), str) or not row["task"]:
            raise ValueError(f"line {index}: missing task")
        expected = row.get("expected_contains")
        if not isinstance(expected, list) or any(not isinstance(item, str) for item in expected):
            raise ValueError(f"line {index}: expected_contains must be a list of strings")
    return rows


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-jsonl", type=Path, required=True)
    parser.add_argument("--image-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-id", default=DEFAULT_MODEL)
    parser.add_argument("--adapter", type=Path, help="optional PEFT adapter directory")
    parser.add_argument("--max-new-tokens", type=int, default=64)
    parser.add_argument("--validate-only", action="store_true")
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    if args.max_new_tokens < 1:
        parser.error("--max-new-tokens must be positive")
    try:
        rows = load_test_rows(args.test_jsonl, args.image_root)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    print(f"Validated {len(rows)} test rows.")
    if args.validate_only:
        return

    try:
        import torch
        from PIL import Image
        from transformers import AutoModelForImageTextToText, AutoProcessor
        if args.adapter:
            from peft import PeftModel
    except ImportError as error:
        parser.error(f"inference dependencies are missing ({error}); see requirements.txt")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    dtype = torch.float16 if device.type == "cuda" else torch.float32
    load_started = time.perf_counter()
    processor = AutoProcessor.from_pretrained(args.model_id)
    model = AutoModelForImageTextToText.from_pretrained(
        args.model_id, torch_dtype=dtype
    ).to(device)
    if args.adapter:
        model = PeftModel.from_pretrained(model, str(args.adapter))
    model.eval()
    model_load_ms = (time.perf_counter() - load_started) * 1000

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as destination:
        for row in rows:
            end_to_end_started = time.perf_counter()
            with Image.open(row["_image_path"]) as source:
                image = source.convert("RGB")
            messages = [{
                "role": "user",
                "content": [
                    {"type": "image", "image": image},
                    {"type": "text", "text": row["messages"][0]["content"]},
                ],
            }]
            inputs = processor.apply_chat_template(
                messages,
                add_generation_prompt=True,
                tokenize=True,
                return_dict=True,
                return_tensors="pt",
            ).to(device)
            preprocessing_ms = (time.perf_counter() - end_to_end_started) * 1000
            prompt_tokens = inputs["input_ids"].shape[-1]
            if device.type == "cuda":
                torch.cuda.reset_peak_memory_stats(device)
            started = time.perf_counter()
            with torch.inference_mode():
                output_ids = model.generate(
                    **inputs, do_sample=False, max_new_tokens=args.max_new_tokens
                )
            generation_ms = (time.perf_counter() - started) * 1000
            generated = output_ids[0, prompt_tokens:]
            generated_tokens = int(generated.numel())
            prediction = processor.decode(generated, skip_special_tokens=True).strip()
            result = {
                "sample_id": row["sample_id"],
                "image": row["image"],
                "task": row["task"],
                "prediction": prediction,
                "model_id": args.model_id,
                "adapter": str(args.adapter) if args.adapter else None,
                "runtime_metrics": {
                    "model_load_ms": model_load_ms,
                    "preprocessing_ms": preprocessing_ms,
                    "generation_ms": generation_ms,
                    "end_to_end_ms": (time.perf_counter() - end_to_end_started) * 1000,
                    "generated_tokens": generated_tokens,
                    "tokens_per_second": generated_tokens * 1000 / generation_ms if generation_ms else 0,
                },
            }
            if device.type == "cuda":
                result["runtime_metrics"]["torch_cuda_peak_allocated_mb"] = (
                    torch.cuda.max_memory_allocated(device) / (1024 * 1024)
                )
            destination.write(json.dumps(result, ensure_ascii=False) + "\n")
            destination.flush()
            print(f"{row['sample_id']} {generated_tokens} tokens {generation_ms:.0f} ms")


if __name__ == "__main__":
    main()
