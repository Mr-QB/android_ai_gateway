#!/usr/bin/env python3
"""Validate and split Vietnamese VLM JSONL by image, never by row."""
import argparse
import hashlib
import json
import random
from collections import Counter, defaultdict
from pathlib import Path

TASKS = {
    "object_recognition", "scene_description", "spatial_description",
    "safety_warning", "obstacle_awareness", "ocr", "human_action", "visual_qa",
}


def load_rows(source: Path, image_root: Path):
    rows = []
    sample_ids = set()
    for line_number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"line {line_number}: invalid JSON ({error.msg})") from None
        if not isinstance(row, dict):
            raise ValueError(f"line {line_number}: each JSONL row must be an object")
        task = row.get("task")
        if not isinstance(task, str) or task not in TASKS:
            raise ValueError(f"line {line_number}: unknown task {row.get('task')!r}")
        image_value = row.get("image")
        if not isinstance(image_value, str) or not image_value.strip():
            raise ValueError(f"line {line_number}: image must be a non-empty relative path")
        image = Path(image_value)
        root = image_root.resolve()
        resolved = (root / image).resolve()
        try:
            resolved.relative_to(root)
        except ValueError:
            raise ValueError(f"line {line_number}: image path escapes --image-root") from None
        if not resolved.is_file():
            raise ValueError(f"line {line_number}: missing image {image}")
        messages = row.get("messages")
        if (
            not isinstance(messages, list)
            or len(messages) != 2
            or any(not isinstance(message, dict) for message in messages)
            or [message.get("role") for message in messages] != ["user", "assistant"]
        ):
            raise ValueError(f"line {line_number}: expected one user and one assistant message")
        if any(not isinstance(m.get("content"), str) or not m["content"].strip() for m in messages):
            raise ValueError(f"line {line_number}: message content must be non-empty text")
        row["image"] = resolved.relative_to(root).as_posix()
        identity = json.dumps(
            [row["image"], row["task"], messages[0]["content"]],
            ensure_ascii=False,
            separators=(",", ":"),
        )
        row["sample_id"] = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]
        if row["sample_id"] in sample_ids:
            raise ValueError(f"line {line_number}: duplicate image/task/question sample")
        sample_ids.add(row["sample_id"])
        rows.append(row)
    if len({row["image"] for row in rows}) < 3:
        raise ValueError("at least three unique images are required to create non-empty splits")
    return rows


def split_rows(rows, seed, ratios):
    by_image = defaultdict(list)
    for row in rows:
        by_image[row["image"]].append(row)
    images = list(by_image)
    random.Random(seed).shuffle(images)
    train_count = max(1, min(len(images) - 2, round(len(images) * ratios[0])))
    validation_count = max(1, min(len(images) - train_count - 1, round(len(images) * ratios[1])))
    validation_end = train_count + validation_count
    assignments = {
        "train": images[:train_count],
        "validation": images[train_count:validation_end],
        "test": images[validation_end:],
    }
    return {name: [row for image in assigned for row in by_image[image]] for name, assigned in assignments.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="source JSONL")
    parser.add_argument("--image-root", type=Path, required=True, help="root for image paths in JSONL")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--ratios", type=float, nargs=3, default=(0.8, 0.1, 0.1), metavar=("TRAIN", "VALIDATION", "TEST"))
    args = parser.parse_args()
    if any(r <= 0 for r in args.ratios) or abs(sum(args.ratios) - 1) > 1e-6:
        parser.error("split ratios must be positive and sum to 1")
    try:
        rows = load_rows(args.input, args.image_root)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    splits = split_rows(rows, args.seed, args.ratios)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = {"seed": args.seed, "splits": {}}
    for name, split in splits.items():
        (args.output_dir / f"{name}.jsonl").write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in split), encoding="utf-8")
        report["splits"][name] = {
            "rows": len(split), "unique_images": len({row['image'] for row in split}),
            "task_distribution": dict(Counter(row["task"] for row in split)),
        }
    (args.output_dir / "split_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
