#!/usr/bin/env python3
"""Score saved model predictions against expected Vietnamese phrases."""
import argparse
import json
import re
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path


def normalize(text):
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9\s]", " ", text)).strip()


def read_jsonl(path):
    rows = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"{path}: line {line_number}: invalid JSON ({error.msg})") from None
        if not isinstance(row, dict):
            raise ValueError(f"{path}: line {line_number}: each JSONL row must be an object")
        rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--references", type=Path, required=True, help="test.jsonl with expected_contains phrases")
    parser.add_argument("--predictions", type=Path, required=True, help="JSONL rows with a prediction field")
    parser.add_argument("--output", type=Path, help="optional JSON report path")
    args = parser.parse_args()
    try:
        refs, preds = read_jsonl(args.references), read_jsonl(args.predictions)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if len(refs) != len(preds):
        parser.error(f"row count mismatch: {len(refs)} references vs {len(preds)} predictions")
    by_task = defaultdict(Counter)
    runtime = defaultdict(list)
    review_fields = ("correct_object", "correct_direction", "correct_warning", "understandable_vietnamese", "hallucination", "concise")
    for index, (ref, pred) in enumerate(zip(refs, preds), 1):
        image = ref.get("image")
        if not isinstance(image, str) or not image:
            parser.error(f"reference row {index} is missing an image identifier")
        if pred.get("image") != image:
            parser.error(
                f"prediction image mismatch on row {index}: expected {image}, got {pred.get('image')!r}"
            )
        sample_id = ref.get("sample_id")
        if not isinstance(sample_id, str) or not sample_id:
            parser.error(f"reference row {index} is missing a sample_id")
        if pred.get("sample_id") != sample_id:
            parser.error(
                f"prediction sample_id mismatch on row {index}: expected {sample_id}, got {pred.get('sample_id')!r}"
            )
        task = ref.get("task")
        if not isinstance(task, str) or not task:
            parser.error(f"reference row {index} is missing a task")
        expected = ref.get("expected_contains", [])
        if not isinstance(expected, list) or any(not isinstance(phrase, str) for phrase in expected):
            parser.error(f"reference row {index} expected_contains must be a list of strings")
        answer = normalize(str(pred.get("prediction", "")))
        hits = sum(normalize(phrase) in answer for phrase in expected)
        by_task[task]["rows"] += 1
        by_task[task]["expected_phrases"] += len(expected)
        by_task[task]["phrase_hits"] += hits
        by_task[task]["empty_predictions"] += not bool(answer)
        by_task[task]["word_count"] += len(answer.split())
        review = pred.get("review", {})
        if not isinstance(review, dict):
            parser.error(f"prediction row {index} review must be an object")
        for field in review_fields:
            if isinstance(review.get(field), bool):
                by_task[task][f"review_{field}_total"] += 1
                by_task[task][f"review_{field}_positive"] += review[field]
        metrics = pred.get("runtime_metrics", {})
        if not isinstance(metrics, dict):
            parser.error(f"prediction row {index} runtime_metrics must be an object")
        for field, value in metrics.items():
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                runtime[field].append(value)
    report = {task: {
        "rows": counts["rows"], "phrase_recall": counts["phrase_hits"] / counts["expected_phrases"] if counts["expected_phrases"] else None,
        "empty_predictions": counts["empty_predictions"], "mean_normalized_word_count": counts["word_count"] / counts["rows"],
        "human_review_rates": {field: counts[f"review_{field}_positive"] / counts[f"review_{field}_total"] for field in review_fields if counts[f"review_{field}_total"]},
    } for task, counts in sorted(by_task.items())}
    report = {"tasks": report, "runtime_metric_means": {field: sum(values) / len(values) for field, values in sorted(runtime.items()) if values}}
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
