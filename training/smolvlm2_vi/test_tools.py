import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import import_viettravelvqa as viettravel_importer
from audit_viettravelvqa import (
    audit_rows,
    classify_license,
    commons_title,
    normalize_source_url,
    parse_commons_response,
)

ROOT = Path(__file__).parent


class TrainingToolsTest(unittest.TestCase):
    def test_viettravel_license_classifier_is_conservative(self):
        self.assertEqual(classify_license("CC-BY-4.0"), "CC-BY")
        self.assertEqual(classify_license("CC-Zero"), "CC0")
        self.assertEqual(classify_license("CC-PD-Mark"), "CC-PD-MARK")
        self.assertEqual(classify_license("Public domain"), "PUBLIC-DOMAIN")
        self.assertEqual(classify_license("CC-BY-SA-4.0"), "CC-BY-SA")
        self.assertEqual(classify_license("None"), "MISSING")
        self.assertEqual(classify_license("custom license"), "OTHER")

    def test_viettravel_audit_preserves_path_case_and_rejects_license_conflicts(self):
        rows = {
            "train": [
                {"source": {"license": "CC-BY-4.0", "url": "https://UPLOAD.wikimedia.org/a/Photo.JPG?x=1"}},
                {"source": {"license": "CC-BY-4.0", "url": "https://upload.wikimedia.org/a/Photo.JPG"}},
                {"source": {"license": "CC-BY-SA-4.0", "url": "https://upload.wikimedia.org/a/Shared.jpg"}},
            ],
            "test": [
                {"source": {"license": "CC-BY-4.0", "url": "https://upload.wikimedia.org/a/Photo.JPG"}},
                {"source": {"license": "CC-BY-4.0", "url": "https://upload.wikimedia.org/a/photo.jpg"}},
                {"source": {"license": "CC0", "url": "https://upload.wikimedia.org/a/Shared.jpg"}},
                {"source": {"license": None, "url": ""}},
            ],
        }
        report = audit_rows(rows)
        self.assertEqual(normalize_source_url("HTTPS://UPLOAD.wikimedia.org/a/Photo.JPG?x=1"), "https://upload.wikimedia.org/a/Photo.JPG")
        self.assertEqual(report["train_test_source_url_overlap"], 2)
        self.assertEqual(report["source_urls_with_conflicting_license_labels"], 1)
        self.assertEqual(report["unique_urls_with_one_allowed_license"], 2)
        self.assertEqual(report["missing_source_urls"]["test"], 1)

    def test_viettravel_commons_metadata_matches_license_and_keeps_attribution(self):
        candidate = {
            "source_url": "https://upload.wikimedia.org/a/ab/Ph%E1%BB%91.JPG",
            "license_kind": "CC-BY",
        }
        self.assertEqual(commons_title(candidate["source_url"]), "File:Phố.JPG")
        payload = {
            "query": {
                "pages": {
                    "1": {
                        "title": "File:Phố.JPG",
                        "imageinfo": [{
                            "url": "https://upload.wikimedia.org/a/ab/Ph%E1%BB%91.JPG",
                            "sha1": "abc123",
                            "thumburl": "https://thumb.wikimedia.org/thumb/example.jpg",
                            "thumbwidth": 1024,
                            "thumbheight": 682,
                            "extmetadata": {
                                "LicenseShortName": {"value": "CC BY 4.0"},
                                "LicenseUrl": {"value": "https://creativecommons.org/licenses/by/4.0/"},
                                "AttributionRequired": {"value": "true"},
                                "Artist": {"value": "Example Author"},
                                "Credit": {"value": "Example Author / Wikimedia Commons"},
                            },
                        }],
                    }
                }
            }
        }
        result = parse_commons_response([candidate], payload)[0]
        self.assertEqual(result["status"], "license_match")
        self.assertEqual(result["artist"], "Example Author")
        self.assertEqual(result["attribution_required"], "true")
        self.assertEqual(result["sha1"], "abc123")
        self.assertEqual(result["thumbnail_url"], "https://thumb.wikimedia.org/thumb/example.jpg")
        self.assertEqual(result["thumbnail_width"], 1024)

    def test_viettravel_commons_mismatch_and_missing_file_are_not_accepted(self):
        candidates = [
            {"source_url": "https://upload.wikimedia.org/a/Shared.jpg", "license_kind": "CC-BY"},
            {"source_url": "https://upload.wikimedia.org/a/Gone.jpg", "license_kind": "CC0"},
        ]
        payload = {
            "query": {
                "pages": {
                    "1": {"title": "File:Shared.jpg", "imageinfo": [{"extmetadata": {"LicenseShortName": {"value": "CC BY-SA 4.0"}}}]},
                    "2": {"title": "File:Gone.jpg", "missing": True},
                }
            }
        }
        results = parse_commons_response(candidates, payload)
        self.assertEqual([row["status"] for row in results], ["license_mismatch", "missing_file_page"])

    def test_viettravel_public_domain_mark_needs_human_page_review(self):
        candidate = {"source_url": "https://upload.wikimedia.org/a/OldPhoto.jpg", "license_kind": "CC-PD-MARK"}
        payload = {"query": {"pages": {"1": {
            "title": "File:OldPhoto.jpg",
            "imageinfo": [{"extmetadata": {"LicenseShortName": {"value": "Public domain"}}}],
        }}}}
        result = parse_commons_response([candidate], payload)[0]
        self.assertEqual(result["status"], "public_domain_review")

    def test_viettravel_importer_accepts_only_exact_commons_license_matches(self):
        audit = {"commons_candidates": [
            {"source_url": "https://upload.wikimedia.org/a/a.jpg", "status": "license_match", "license_kind": "CC-BY", "sha1": "a" * 40},
            {"source_url": "https://upload.wikimedia.org/a/b.jpg", "status": "license_match", "license_kind": "CC-BY-SA", "sha1": "b" * 40},
            {"source_url": "https://upload.wikimedia.org/a/c.jpg", "status": "public_domain_review", "license_kind": "CC-PD-MARK", "sha1": "c" * 40},
            {"source_url": "https://upload.wikimedia.org/a/d.jpg", "status": "license_match", "license_kind": "CC0", "sha1": ""},
        ]}

        candidates = viettravel_importer.verified_candidates(audit)

        self.assertEqual(list(candidates), ["https://upload.wikimedia.org/a/a.jpg"])

    def test_viettravel_importer_keeps_concise_answers_and_long_ocr_answers(self):
        rows = [
            {"messages": [
                {"role": "user", "content": "Đây là gì?"},
                {"role": "assistant", "content": "Xe buýt."},
            ]},
            {"messages": [
                {"role": "user", "content": "Mô tả cảnh vật."},
                {"role": "assistant", "content": "Từ " + "một " * 31 + "câu."},
            ]},
            {"messages": [
                {"role": "user", "content": "Đọc chữ trên biển."},
                {"role": "assistant", "content": "Từ " + "một " * 31 + "câu."},
            ]},
        ]

        selected, filtered = viettravel_importer.curate_training_rows(rows)

        self.assertEqual(len(selected), 2)
        self.assertEqual(filtered, 1)
        self.assertEqual(selected[0]["expected_contains"], ["Xe buýt."])
        self.assertTrue(selected[1]["expected_contains"][0].startswith("Từ "))

    def test_viettravel_importer_excludes_duplicate_and_conflicting_answers(self):
        url = "https://upload.wikimedia.org/a/scene.jpg"
        candidate = {url: {
            "source_url": url,
            "sha1": "a" * 40,
            "thumbnail_url": "https://thumb.wikimedia.org/thumb/scene.jpg",
            "thumbnail_width": 1024,
            "thumbnail_height": 768,
            "commons_license": "CC BY 4.0",
            "commons_license_url": "https://creativecommons.org/licenses/by/4.0/",
            "attribution_required": "true",
            "artist": "Author",
            "credit": "Credit",
        }}

        def row(question, answer):
            return {
                "source": {"url": url, "license": "CC-BY-4.0"},
                "messages": [
                    {"role": "user", "content": question},
                    {"role": "assistant", "content": answer},
                ],
            }

        rows = {"train": [
            row("Đây là gì?", "Xe buýt."),
            row("Đây là gì?", "Xe buýt."),
            row("Đây là gì?", "Xe tải."),
            row("Màu gì?", "Màu đỏ."),
        ], "test": []}

        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            fake_image = output / "images" / ("a" * 40 + ".jpg")
            with patch.object(viettravel_importer, "download_image", return_value=(fake_image, 4, "JPEG")):
                report = viettravel_importer.import_rows(rows, candidate, output, delay=0)

            examples = [json.loads(line) for line in (output / "all.jsonl").read_text(encoding="utf-8").splitlines()]
            attribution = json.loads((output / "attributions.jsonl").read_text(encoding="utf-8"))

        self.assertEqual(len(examples), 1)
        self.assertEqual(examples[0]["messages"][0]["content"], "Màu gì?")
        self.assertEqual(report["duplicate_question_rows_removed"], 1)
        self.assertEqual(report["conflicting_questions_excluded"], 1)
        self.assertEqual(attribution["artist_html"], "Author")
        self.assertEqual(attribution["image_sha1"], "a" * 40)

    def test_viettravel_importer_rejects_invalid_thumbnail_payload(self):
        class FakeResponse:
            sent = False

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self, _size):
                if self.sent:
                    return b""
                self.sent = True
                return b"not the expected image"

        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError, "supported image"):
                viettravel_importer.download_image(
                    {
                        "source_url": "https://upload.wikimedia.org/a/image.jpg",
                        "thumbnail_url": "https://thumb.wikimedia.org/thumb/image.jpg",
                        "sha1": "0" * 40,
                    },
                    Path(temp),
                    opener=lambda *_args, **_kwargs: FakeResponse(),
                )
            self.assertEqual(list(Path(temp).iterdir()), [])

    def test_trainer_validates_jsonl_without_loading_training_dependencies(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scene.jpg").write_bytes(b"fixture")
            row = {
                "image": "scene.jpg",
                "messages": [
                    {"role": "user", "content": "Phía trước có gì?"},
                    {"role": "assistant", "content": "Có một chiếc xe buýt."},
                ],
            }
            source = root / "train.jsonl"
            source.write_text(json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "train_lora.py"), "--validate-only", "--train-jsonl", str(source), "--image-root", str(root)],
                check=True, capture_output=True, text=True,
            )
            self.assertIn("Validated 1 training rows", result.stdout)

    def test_trainer_rejects_image_path_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            row = {
                "image": "../outside.jpg",
                "messages": [
                    {"role": "user", "content": "Phía trước có gì?"},
                    {"role": "assistant", "content": "Có một chiếc xe buýt."},
                ],
            }
            source = root / "train.jsonl"
            source.write_text(json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "train_lora.py"), "--validate-only", "--train-jsonl", str(source), "--image-root", str(root)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("escapes image root", result.stderr)

    def test_trainer_reports_invalid_image_type_as_data_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            row = {
                "image": 123,
                "messages": [
                    {"role": "user", "content": "Phía trước có gì?"},
                    {"role": "assistant", "content": "Có một chiếc xe buýt."},
                ],
            }
            source = root / "train.jsonl"
            source.write_text(json.dumps(row) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "train_lora.py"), "--validate-only", "--train-jsonl", str(source), "--image-root", str(root)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("line 1: image must be a non-empty relative path", result.stderr)

    def test_splitter_reports_non_object_jsonl_row_as_data_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            images = root / "images"
            images.mkdir()
            source = root / "all.jsonl"
            source.write_text("[]\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "prepare_dataset.py"), "--input", str(source), "--image-root", str(images), "--output-dir", str(root / "splits")],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("line 1: each JSONL row must be an object", result.stderr)

    def test_trainer_rejects_train_validation_image_leakage(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scene.jpg").write_bytes(b"fixture")
            row = {
                "image": "scene.jpg",
                "messages": [
                    {"role": "user", "content": "Phía trước có gì?"},
                    {"role": "assistant", "content": "Có một chiếc xe buýt."},
                ],
            }
            train = root / "train.jsonl"
            validation = root / "validation.jsonl"
            encoded = json.dumps(row, ensure_ascii=False) + "\n"
            train.write_text(encoded, encoding="utf-8")
            validation.write_text(encoded, encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "train_lora.py"),
                    "--validate-only",
                    "--train-jsonl",
                    str(train),
                    "--validation-jsonl",
                    str(validation),
                    "--image-root",
                    str(root),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("share 1 image(s)", result.stderr)

    def test_split_keeps_same_image_together_and_eval_scores_phrases(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            images = root / "images"
            images.mkdir()
            (images / "sub").mkdir()
            rows = []
            for index in range(3):
                (images / f"{index}.jpg").write_bytes(b"fixture")
                rows.append({"image": f"{index}.jpg", "task": "visual_qa", "messages": [{"role": "user", "content": "\u0110\u00e2y l\u00e0 g\u00ec?"}, {"role": "assistant", "content": "Xe \u0111\u1ea1p."}], "expected_contains": ["xe \u0111\u1ea1p"]})
            alias = dict(rows[0])
            alias["image"] = "sub/../0.jpg"
            alias["messages"] = [dict(message) for message in rows[0]["messages"]]
            alias["messages"][0]["content"] = "What else is visible?"
            rows.append(alias)
            source = root / "all.jsonl"
            source.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
            output = root / "splits"
            subprocess.run([sys.executable, str(ROOT / "prepare_dataset.py"), "--input", str(source), "--image-root", str(images), "--output-dir", str(output)], check=True, capture_output=True, text=True)
            splits = {name: [json.loads(line) for line in (output / f"{name}.jsonl").read_text(encoding="utf-8").splitlines()] for name in ("train", "validation", "test")}
            image_sets = [{row["image"] for row in part} for part in splits.values()]
            self.assertFalse(image_sets[0] & image_sets[1] or image_sets[0] & image_sets[2] or image_sets[1] & image_sets[2])
            self.assertEqual(sum(map(len, splits.values())), len(rows))
            zero_image_splits = [
                part
                for part in splits.values()
                if any(row["image"] == "0.jpg" for row in part)
            ]
            self.assertEqual(len(zero_image_splits), 1)
            self.assertEqual(
                sum(row["image"] == "0.jpg" for row in zero_image_splits[0]), 2
            )
            reference = output / "test.jsonl"
            prediction = root / "predictions.jsonl"
            prediction.write_text("".join(json.dumps({"sample_id": row["sample_id"], "image": row["image"], "prediction": "C\u00f3 m\u1ed9t XE \u0110\u1ea0P \u1edf ph\u00eda tr\u01b0\u1edbc.", "review": {"correct_object": True, "hallucination": False}, "runtime_metrics": {"ttft_ms": 321}}, ensure_ascii=False) + "\n" for row in splits["test"]), encoding="utf-8")
            report = root / "report.json"
            subprocess.run([sys.executable, str(ROOT / "evaluate.py"), "--references", str(reference), "--predictions", str(prediction), "--output", str(report)], check=True, capture_output=True, text=True)
            scored = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(scored["tasks"]["visual_qa"]["phrase_recall"], 1.0)
            self.assertEqual(scored["tasks"]["visual_qa"]["human_review_rates"]["correct_object"], 1.0)
            self.assertEqual(scored["runtime_metric_means"]["ttft_ms"], 321)

    def test_evaluator_rejects_prediction_for_wrong_image(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            references = root / "references.jsonl"
            references.write_text(json.dumps({"sample_id": "expected-id", "image": "scene.jpg", "task": "visual_qa", "expected_contains": ["xe máy"]}) + "\n", encoding="utf-8")
            predictions = root / "predictions.jsonl"
            predictions.write_text(json.dumps({"sample_id": "expected-id", "image": "other.jpg", "prediction": "xe máy"}) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "evaluate.py"), "--references", str(references), "--predictions", str(predictions)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("prediction image mismatch", result.stderr)

    def test_evaluator_rejects_wrong_question_for_same_image(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            references = root / "references.jsonl"
            references.write_text(json.dumps({"sample_id": "question-a", "image": "scene.jpg", "task": "visual_qa", "expected_contains": ["xe máy"]}) + "\n", encoding="utf-8")
            predictions = root / "predictions.jsonl"
            predictions.write_text(json.dumps({"sample_id": "question-b", "image": "scene.jpg", "prediction": "xe máy"}) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "evaluate.py"), "--references", str(references), "--predictions", str(predictions)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("prediction sample_id mismatch", result.stderr)

    def test_evaluator_reports_non_object_row_as_data_error(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            references = root / "references.jsonl"
            references.write_text("null\n", encoding="utf-8")
            predictions = root / "predictions.jsonl"
            predictions.write_text("{}\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "evaluate.py"), "--references", str(references), "--predictions", str(predictions)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("each JSONL row must be an object", result.stderr)

    def test_paired_comparison_scores_identical_rows_and_runtime_delta(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            references = [
                {"sample_id": "a", "image": "a.jpg", "task": "visual_qa", "expected_contains": ["xe máy", "bên phải"]},
                {"sample_id": "b", "image": "b.jpg", "task": "safety_warning", "expected_contains": ["người"]},
            ]
            baseline = [
                {"sample_id": "a", "image": "a.jpg", "prediction": "xe máy", "runtime_metrics": {"generation_ms": 900}},
                {"sample_id": "b", "image": "b.jpg", "prediction": "người", "runtime_metrics": {"generation_ms": 900}},
            ]
            candidate = [
                {"sample_id": "a", "image": "a.jpg", "prediction": "xe máy bên phải", "runtime_metrics": {"generation_ms": 700}},
                {"sample_id": "b", "image": "b.jpg", "prediction": "trống", "runtime_metrics": {"generation_ms": 700}},
            ]
            paths = [root / name for name in ("refs.jsonl", "base.jsonl", "candidate.jsonl")]
            for path, rows in zip(paths, (references, baseline, candidate)):
                path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "compare_models.py"), "--references", str(paths[0]), "--baseline", str(paths[1]), "--candidate", str(paths[2])],
                check=True, capture_output=True, text=True,
            )
            report = json.loads(result.stdout)
            self.assertEqual(report["paired_rows"], 2)
            self.assertEqual(report["paired_phrase_recall_outcomes"]["candidate_better"], 1)
            self.assertEqual(report["paired_phrase_recall_outcomes"]["baseline_better"], 1)
            self.assertEqual(report["tasks"]["visual_qa"]["phrase_recall_delta"], 0.5)
            self.assertEqual(report["tasks"]["visual_qa"]["candidate"]["runtime_metric_means"]["generation_ms"], 700)
            self.assertEqual(report["tasks"]["visual_qa"]["runtime_metric_deltas"]["generation_ms"], -200)

    def test_paired_comparison_rejects_a_misaligned_candidate(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            references = root / "refs.jsonl"
            references.write_text(json.dumps({"sample_id": "expected", "image": "scene.jpg", "task": "visual_qa", "expected_contains": ["xe máy"]}) + "\n", encoding="utf-8")
            baseline = root / "base.jsonl"
            baseline.write_text(json.dumps({"sample_id": "expected", "image": "scene.jpg", "prediction": "xe máy"}) + "\n", encoding="utf-8")
            candidate = root / "candidate.jsonl"
            candidate.write_text(json.dumps({"sample_id": "wrong", "image": "scene.jpg", "prediction": "xe máy"}) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "compare_models.py"), "--references", str(references), "--baseline", str(baseline), "--candidate", str(candidate)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("candidate prediction mismatch", result.stderr)

    def test_predictor_validates_fixed_test_rows_without_model_dependencies(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scene.jpg").write_bytes(b"fixture")
            row = {
                "image": "scene.jpg",
                "sample_id": "sample-1",
                "task": "visual_qa",
                "expected_contains": ["xe đạp"],
                "messages": [
                    {"role": "user", "content": "Đây là gì?"},
                    {"role": "assistant", "content": "Xe đạp."},
                ],
            }
            source = root / "test.jsonl"
            source.write_text(json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "predict.py"), "--test-jsonl", str(source), "--image-root", str(root), "--output", str(root / "predictions.jsonl"), "--validate-only"],
                check=True, capture_output=True, text=True,
            )
            self.assertIn("Validated 1 test rows", result.stdout)

    def test_predictor_requires_prepared_sample_ids(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scene.jpg").write_bytes(b"fixture")
            row = {
                "image": "scene.jpg",
                "task": "visual_qa",
                "expected_contains": ["xe đạp"],
                "messages": [
                    {"role": "user", "content": "Đây là gì?"},
                    {"role": "assistant", "content": "Xe đạp."},
                ],
            }
            source = root / "test.jsonl"
            source.write_text(json.dumps(row, ensure_ascii=False) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "predict.py"), "--test-jsonl", str(source), "--image-root", str(root), "--output", str(root / "predictions.jsonl"), "--validate-only"],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("missing stable sample_id", result.stderr)


if __name__ == "__main__":
    unittest.main()
