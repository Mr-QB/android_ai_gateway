#!/usr/bin/env python3
"""Compare two models on the exact same image/question test rows."""
import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from evaluate import normalize, read_jsonl

REVIEW_FIELDS = (
    "correct_object", "correct_direction", "correct_warning",
    "understandable_vietnamese", "hallucination", "concise",
)


def score_rows(references, predictions):
    by_task = defaultdict(lambda: {
        "rows": 0, "hits": 0, "expected": 0, "words": 0,
        "empty": 0, "review": Counter(), "runtime": defaultdict(list),
    })
    per_row = {}
    for reference, prediction in zip(references, predictions):
        task = reference["task"]
        expected = reference.get("expected_contains", [])
        answer = normalize(str(prediction.get("prediction", "")))
        hits = sum(normalize(phrase) in answer for phrase in expected)
        row_recall = hits / len(expected) if expected else None
        per_row[reference["sample_id"]] = row_recall
        scores = by_task[task]
        scores["rows"] += 1
        scores["hits"] += hits
        scores["expected"] += len(expected)
        scores["words"] += len(answer.split())
        scores["empty"] += not bool(answer)
        review = prediction.get("review", {})
        for field in REVIEW_FIELDS:
            if isinstance(review.get(field), bool):
                scores["review"][field] += int(review[field])
                scores["review"][f"{field}_count"] += 1
        for field, value in prediction.get("runtime_metrics", {}).items():
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                scores["runtime"][field].append(value)

    report = {}
    for task, scores in sorted(by_task.items()):
        report[task] = {
            "rows": scores["rows"],
            "phrase_recall": scores["hits"] / scores["expected"] if scores["expected"] else None,
            "empty_predictions": scores["empty"],
            "mean_word_count": scores["words"] / scores["rows"],
            "human_review_rates": {
                field: scores["review"][field] / scores["review"][f"{field}_count"]
                for field in REVIEW_FIELDS if scores["review"][f"{field}_count"]
            },
            "runtime_metric_means": {
                field: sum(values) / len(values)
                for field, values in sorted(scores["runtime"].items()) if values
            },
        }
    return report, per_row


def compare(references, baseline, candidate):
    if len(references) != len(baseline) or len(references) != len(candidate):
        raise ValueError("reference and prediction row counts must match")
    task_by_sample_id = {}
    for index, reference in enumerate(references, 1):
        sample_id = reference.get("sample_id")
        image = reference.get("image")
        task = reference.get("task")
        expected = reference.get("expected_contains", [])
        if not isinstance(sample_id, str) or not sample_id:
            raise ValueError(f"reference row {index} is missing a sample_id")
        if sample_id in task_by_sample_id:
            raise ValueError(f"reference row {index} duplicates sample_id {sample_id!r}")
        if not isinstance(image, str) or not image:
            raise ValueError(f"reference row {index} is missing an image")
        if not isinstance(task, str) or not task:
            raise ValueError(f"reference row {index} is missing a task")
        task_by_sample_id[sample_id] = task
        if not isinstance(expected, list) or any(not isinstance(phrase, str) for phrase in expected):
            raise ValueError(f"reference row {index} expected_contains must be a list of strings")
        for name, prediction in (("baseline", baseline[index - 1]), ("candidate", candidate[index - 1])):
            if prediction.get("sample_id") != sample_id or prediction.get("image") != image:
                raise ValueError(
                    f"{name} prediction mismatch on row {index}: expected sample_id={sample_id!r}, image={image!r}"
                )
            if not isinstance(prediction.get("review", {}), dict):
                raise ValueError(f"{name} prediction row {index} review must be an object")
            if not isinstance(prediction.get("runtime_metrics", {}), dict):
                raise ValueError(f"{name} prediction row {index} runtime_metrics must be an object")

    baseline_report, baseline_rows = score_rows(references, baseline)
    candidate_report, candidate_rows = score_rows(references, candidate)
    paired = Counter()
    paired_by_task = defaultdict(Counter)
    for sample_id, baseline_recall in baseline_rows.items():
        candidate_recall = candidate_rows[sample_id]
        task = task_by_sample_id[sample_id]
        if baseline_recall is None or candidate_recall is None:
            paired["not_scored"] += 1
            paired_by_task[task]["not_scored"] += 1
        elif candidate_recall > baseline_recall:
            paired["candidate_better"] += 1
            paired_by_task[task]["candidate_better"] += 1
        elif candidate_recall < baseline_recall:
            paired["baseline_better"] += 1
            paired_by_task[task]["baseline_better"] += 1
        else:
            paired["tied"] += 1
            paired_by_task[task]["tied"] += 1

    tasks = {}
    for task in sorted(set(baseline_report) | set(candidate_report)):
        base = baseline_report[task]
        cand = candidate_report[task]
        base_recall, cand_recall = base["phrase_recall"], cand["phrase_recall"]
        base_review = base["human_review_rates"]
        cand_review = cand["human_review_rates"]
        base_runtime = base["runtime_metric_means"]
        cand_runtime = cand["runtime_metric_means"]
        tasks[task] = {
            "baseline": base,
            "candidate": cand,
            "phrase_recall_delta": cand_recall - base_recall if base_recall is not None and cand_recall is not None else None,
            "human_review_rate_deltas": {
                field: cand_review[field] - base_review[field]
                for field in base_review.keys() & cand_review.keys()
            },
            "runtime_metric_deltas": {
                field: cand_runtime[field] - base_runtime[field]
                for field in base_runtime.keys() & cand_runtime.keys()
            },
            "mean_word_count_delta": cand["mean_word_count"] - base["mean_word_count"],
            "paired_phrase_recall_outcomes": dict(paired_by_task[task]),
        }
    return {
        "paired_rows": len(references),
        "paired_phrase_recall_outcomes": dict(paired),
        "tasks": tasks,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--references", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = compare(
            read_jsonl(args.references),
            read_jsonl(args.baseline),
            read_jsonl(args.candidate),
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
