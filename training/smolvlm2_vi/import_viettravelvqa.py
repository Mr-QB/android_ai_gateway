#!/usr/bin/env python3
"""Import only Commons-verified VietTravelVQA images into an ignored data directory."""
import argparse
import hashlib
import json
import mimetypes
import re
import time
from collections import defaultdict
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from audit_viettravelvqa import fetch_commons_metadata, fetch_rows, normalize_source_url

DATASET_CITATION = "Nguyen et al., VietTravelVQA v2, Mendeley Data, doi:10.17632/fvxtpnh8mh.2"
MAX_IMAGE_BYTES = 50 * 1024 * 1024
IMPORTABLE_KINDS = {"CC-BY", "CC0"}
OCR_QUERY = re.compile(
    r"đọc|chữ|ký tự|nội dung|ghi (?:gì|lại)|biển báo.*(?:ghi|viết)",
    re.IGNORECASE,
)


def verified_candidates(audit_report):
    """Return only source URLs whose Commons license category exactly matched."""
    return {
        normalize_source_url(item["source_url"]): item
        for item in audit_report.get("commons_candidates", [])
        if item.get("status") == "license_match"
        and item.get("license_kind") in IMPORTABLE_KINDS
        and item.get("sha1")
    }


def message_text(message):
    content = message.get("content", "")
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    return " ".join(
        part["text"].strip()
        for part in content
        if isinstance(part, dict) and part.get("type") == "text" and isinstance(part.get("text"), str) and part["text"].strip()
    )


def row_messages(row):
    messages = row.get("messages")
    if not isinstance(messages, list):
        return None
    parsed = []
    for message in messages:
        if not isinstance(message, dict) or message.get("role") not in {"user", "assistant"}:
            return None
        text = message_text(message)
        if not text:
            return None
        parsed.append({"role": message["role"], "content": text})
    if len(parsed) != 2 or [item["role"] for item in parsed] != ["user", "assistant"]:
        return None
    return parsed


def curate_training_rows(rows, max_answer_words=30):
    """Keep concise answers, allowing longer responses for explicit OCR questions."""
    selected = []
    filtered = 0
    for source in rows:
        row = dict(source)
        messages = row.get("messages", [])
        if len(messages) != 2 or not all(isinstance(item.get("content"), str) for item in messages):
            continue
        answer = messages[1]["content"]
        row["expected_contains"] = [answer]
        if len(answer.split()) > max_answer_words and not OCR_QUERY.search(messages[0]["content"]):
            filtered += 1
            continue
        selected.append(row)
    return selected, filtered


def download_image(candidate, images_dir, opener=urlopen, max_bytes=MAX_IMAGE_BYTES):
    """Download a Commons thumbnail and verify it is a valid, bounded image."""
    download_url = candidate.get("thumbnail_url")
    if not download_url:
        raise ValueError("Commons did not provide the requested thumbnail")
    if urlsplit(download_url).hostname not in {"thumb.wikimedia.org", "upload.wikimedia.org"}:
        raise ValueError("Commons thumbnail URL has an unexpected host")
    source_sha1 = str(candidate["sha1"]).lower()
    request = Request(
        download_url,
        headers={"User-Agent": "android-ai-gateway-viettravel-import/1.0 (attribution-preserving dataset import)"},
    )
    temp_path = images_dir / f".{source_sha1}.download"
    digest = hashlib.sha1()
    size = 0
    try:
        for attempt in range(5):
            digest = hashlib.sha1()
            size = 0
            try:
                with opener(request, timeout=45) as response, temp_path.open("wb") as output:
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > max_bytes:
                            raise ValueError(f"image exceeds {max_bytes} bytes")
                        digest.update(chunk)
                        output.write(chunk)
                break
            except HTTPError as error:
                temp_path.unlink(missing_ok=True)
                if error.code not in {429, 500, 502, 503, 504} or attempt == 4:
                    raise
                retry_after = error.headers.get("Retry-After")
                time.sleep(float(retry_after) if retry_after and retry_after.isdigit() else min(30, 2 ** (attempt + 1)))
            except (URLError, TimeoutError):
                temp_path.unlink(missing_ok=True)
                if attempt == 4:
                    raise
                time.sleep(min(30, 2 ** (attempt + 1)))
        downloaded_sha1 = digest.hexdigest()
        with temp_path.open("rb") as stream:
            signature = stream.read(16)
        image_format = _image_format(signature)
        if not image_format:
            raise ValueError("downloaded bytes are not a supported image")
        from PIL import Image
        with Image.open(temp_path) as image:
            image.verify()
        suffix = mimetypes.guess_extension(image_format[1]) or ".img"
        destination = images_dir / f"{downloaded_sha1}{suffix}"
        if destination.exists():
            if hashlib.sha1(destination.read_bytes()).hexdigest() != downloaded_sha1:
                raise ValueError(f"existing image has unexpected contents: {destination.name}")
            temp_path.unlink(missing_ok=True)
        else:
            temp_path.replace(destination)
        return destination, size, image_format[0]
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def _image_format(header):
    if header.startswith(b"\xff\xd8\xff"):
        return "JPEG", "image/jpeg"
    if header.startswith(b"\x89PNG\r\n\x1a\n"):
        return "PNG", "image/png"
    if header.startswith((b"GIF87a", b"GIF89a")):
        return "GIF", "image/gif"
    if header.startswith(b"RIFF") and header[8:12] == b"WEBP":
        return "WEBP", "image/webp"
    if header.startswith((b"II*\x00", b"MM\x00*")):
        return "TIFF", "image/tiff"
    return None


def import_rows(rows_by_split, candidates, output_dir, delay=0.25, max_images=None, opener=urlopen):
    images_dir = output_dir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)
    rows_by_url = defaultdict(list)
    for rows in rows_by_split.values():
        for row in rows:
            source = row.get("source")
            if not isinstance(source, dict):
                continue
            url = normalize_source_url(source.get("url"))
            if url not in candidates:
                continue
            messages = row_messages(row)
            if messages:
                rows_by_url[url].append((row, messages))

    selected_urls = sorted(url for url in rows_by_url if url in candidates)
    if max_images is not None:
        selected_urls = selected_urls[:max_images]
    examples = []
    attributions = []
    failures = []
    duplicate_questions = 0
    conflicting_questions = 0
    for index, url in enumerate(selected_urls, 1):
        candidate = candidates[url]
        try:
            image_path, size, image_format = download_image(candidate, images_dir, opener=opener)
        except Exception as error:  # Keep the import moving; failed images get no training rows.
            failures.append({"source_url": url, "error": f"{type(error).__name__}: {error}"})
            print(f"skip {index}/{len(selected_urls)} {url}: {error}", flush=True)
            continue
        relative_image = image_path.relative_to(output_dir).as_posix()
        attributions.append({
            "image": relative_image,
            "image_sha1": image_path.stem,
            "commons_source_sha1": candidate["sha1"],
            "thumbnail_url": candidate["thumbnail_url"],
            "thumbnail_width": candidate.get("thumbnail_width"),
            "thumbnail_height": candidate.get("thumbnail_height"),
            "commons_title": candidate.get("commons_title"),
            "file_page_url": candidate.get("file_page_url"),
            "source_url": url,
            "license": candidate.get("commons_license"),
            "license_url": candidate.get("commons_license_url"),
            "attribution_required": candidate.get("attribution_required"),
            "artist_html": candidate.get("artist"),
            "credit_html": candidate.get("credit"),
            "dataset_citation": DATASET_CITATION,
        })
        question_answers = {}
        conflicted_questions = set()
        for row, messages in rows_by_url[url]:
            key = messages[0]["content"]
            answer = messages[1]["content"]
            previous = question_answers.get(key)
            if previous is not None:
                if previous[0] == answer:
                    duplicate_questions += 1
                else:
                    conflicted_questions.add(key)
                continue
            question_answers[key] = (answer, row, messages)
        conflicting_questions += len(conflicted_questions)
        for question, (answer, row, messages) in question_answers.items():
            if question in conflicted_questions:
                continue
            examples.append({
                "image": relative_image,
                "task": "visual_qa",
                "messages": messages,
                "source_url": url,
                "source_license": (row.get("source") or {}).get("license"),
                "commons_license": candidate.get("commons_license"),
                "commons_license_url": candidate.get("commons_license_url"),
                "commons_file_page": candidate.get("file_page_url"),
                "image_sha1": image_path.stem,
                "commons_source_sha1": candidate["sha1"],
                "difficulty": row.get("difficult"),
                "dataset_citation": DATASET_CITATION,
            })
        print(f"downloaded {index}/{len(selected_urls)} {image_path.name} ({size} bytes, {image_format})", flush=True)
        if delay > 0 and index < len(selected_urls):
            time.sleep(delay)

    output_dir.mkdir(parents=True, exist_ok=True)
    trainable_examples, long_answer_rows_filtered = curate_training_rows(examples)
    _write_jsonl(output_dir / "all.jsonl", [
        {**row, "expected_contains": [row["messages"][1]["content"]]}
        for row in examples
    ])
    _write_jsonl(output_dir / "trainable.jsonl", trainable_examples)
    _write_jsonl(output_dir / "attributions.jsonl", attributions)
    report = {
        "images_downloaded": len(attributions),
        "image_question_rows": len(examples),
        "trainable_question_rows": len(trainable_examples),
        "long_non_ocr_answers_filtered": long_answer_rows_filtered,
        "duplicate_question_rows_removed": duplicate_questions,
        "conflicting_questions_excluded": conflicting_questions,
        "image_download_failures": failures,
        "dataset_citation": DATASET_CITATION,
        "source_license_policy": "CC-BY/CC0 only after exact Commons metadata match; Public Domain Mark rows excluded",
        "image_payloads_downloaded": len(attributions),
    }
    (output_dir / "import_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "image_download_failures"}, ensure_ascii=True, indent=2))
    return report


def _write_jsonl(path, rows):
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit-report", type=Path, required=True, help="full audit output with Commons metadata")
    parser.add_argument("--output-dir", type=Path, required=True, help="ignored local dataset folder")
    parser.add_argument("--page-size", type=int, default=100)
    parser.add_argument("--delay", type=float, default=0.75)
    parser.add_argument("--download-delay", type=float, default=1.5)
    parser.add_argument("--max-rows", type=int, help="limit each split for a small import smoke test")
    parser.add_argument("--max-images", type=int, help="limit verified images for a small import smoke test")
    args = parser.parse_args()
    if not args.audit_report.is_file():
        parser.error(f"audit report does not exist: {args.audit_report}")
    if args.max_rows is not None and args.max_rows <= 0:
        parser.error("--max-rows must be positive")
    if args.max_images is not None and args.max_images <= 0:
        parser.error("--max-images must be positive")
    if args.page_size < 1 or args.page_size > 100 or args.delay < 0 or args.download_delay < 0:
        parser.error("page size must be 1..100 and delays must be non-negative")

    audit = json.loads(args.audit_report.read_text(encoding="utf-8"))
    if audit.get("partial_scan"):
        parser.error("audit report must contain both full dataset splits")
    candidates = verified_candidates(audit)
    if not candidates:
        parser.error("audit report has no Commons license_match candidates")
    refreshed = fetch_commons_metadata(list(candidates.values()), delay=args.delay, batch_size=20)
    candidates = {
        normalize_source_url(item["source_url"]): item
        for item in refreshed
        if item.get("status") == "license_match"
        and item.get("license_kind") in IMPORTABLE_KINDS
        and item.get("sha1")
        and item.get("thumbnail_url")
    }
    if not candidates:
        parser.error("Commons did not return any verified thumbnails")
    rows_by_split = {
        split: fetch_rows(audit["dataset"], audit["config"], split, args.page_size, args.delay, args.max_rows)
        for split in ("train", "test")
    }
    import_rows(rows_by_split, candidates, args.output_dir, delay=args.download_delay, max_images=args.max_images)


if __name__ == "__main__":
    main()
