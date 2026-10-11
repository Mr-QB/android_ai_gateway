#!/usr/bin/env python3
"""Audit VietTravelVQA source-license metadata without downloading images."""
import argparse
import json
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

ALLOWED_KINDS = {"CC-BY", "CC0", "CC-PD-MARK"}
BASE_URL = "https://datasets-server.huggingface.co/rows"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"


def classify_license(value):
    """Map a source license label to a conservative, auditable category."""
    label = " ".join(str(value or "").upper().replace("_", " ").split())
    if not label or label in {"NONE", "<MISSING>"}:
        return "MISSING"
    if "CC-BY-SA" in label or "CC BY-SA" in label:
        return "CC-BY-SA"
    if "CC-ZERO" in label or "CC0" in label:
        return "CC0"
    if "CC-PD-MARK" in label or "PUBLIC DOMAIN MARK" in label:
        return "CC-PD-MARK"
    if "PUBLIC DOMAIN" in label:
        return "PUBLIC-DOMAIN"
    if "CC-BY" in label or "CC BY" in label:
        return "CC-BY"
    return "OTHER"


def normalize_source_url(value):
    """Normalize URL host/query while preserving case-sensitive file paths."""
    if not isinstance(value, str) or not value.strip():
        return None
    parts = urlsplit(value.strip())
    if not parts.scheme or not parts.netloc or not parts.path:
        return None
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), parts.path, "", ""))


def audit_rows(rows_by_split):
    row_counts = {split: 0 for split in rows_by_split}
    license_counts = {split: Counter() for split in rows_by_split}
    urls_by_split = {split: set() for split in rows_by_split}
    url_license_kinds = defaultdict(set)
    missing_urls = {split: 0 for split in rows_by_split}

    for split, rows in rows_by_split.items():
        for row in rows:
            row_counts[split] += 1
            source = row.get("source")
            if not isinstance(source, dict):
                source = {}
            kind = classify_license(source.get("license"))
            license_counts[split][kind] += 1
            url = normalize_source_url(source.get("url"))
            if url is None:
                missing_urls[split] += 1
                continue
            urls_by_split[split].add(url)
            url_license_kinds[url].add(kind)

    clean_urls = {
        url for url, kinds in url_license_kinds.items()
        if len(kinds) == 1 and next(iter(kinds)) in ALLOWED_KINDS
    }
    candidate_urls = [
        {"source_url": url, "license_kind": next(iter(url_license_kinds[url]))}
        for url in sorted(clean_urls)
    ]
    overlap = set.intersection(*urls_by_split.values()) if len(urls_by_split) > 1 else set()
    return {
        "rows": row_counts,
        "license_rows": {split: dict(sorted(counts.items())) for split, counts in license_counts.items()},
        "unique_source_urls": {split: len(urls) for split, urls in urls_by_split.items()},
        "missing_source_urls": missing_urls,
        "train_test_source_url_overlap": len(overlap) if {"train", "test"} <= urls_by_split.keys() else None,
        "source_urls_with_conflicting_license_labels": sum(len(kinds) > 1 for kinds in url_license_kinds.values()),
        "unique_urls_with_one_allowed_license": len(clean_urls),
        "candidate_source_urls": candidate_urls,
        "allowed_license_kinds": sorted(ALLOWED_KINDS),
    }


def commons_title(source_url):
    path = urlsplit(source_url).path
    if not path:
        return None
    filename = unquote(path.rsplit("/", 1)[-1])
    return f"File:{filename.replace('_', ' ')}" if filename else None


def _commons_title_key(title):
    namespace, separator, name = title.partition(":")
    if not separator or not name:
        return title.casefold()
    return f"{namespace.casefold()}:{name[:1].upper()}{name[1:]}"


def _metadata_value(metadata, key):
    value = metadata.get(key)
    if isinstance(value, dict):
        value = value.get("value")
    return str(value).strip() if value is not None else ""


def parse_commons_response(candidates, payload):
    """Match candidates against Commons file-page license and attribution metadata."""
    pages = payload.get("query", {}).get("pages", {})
    by_title = defaultdict(list)
    for page in pages.values():
        by_title[_commons_title_key(str(page.get("title", "")))].append(page)
    results = []
    for candidate in candidates:
        title = commons_title(candidate["source_url"])
        result = {**candidate, "commons_title": title, "status": "missing_file_page"}
        if not title:
            result["status"] = "invalid_source_url"
            results.append(result)
            continue
        matches = by_title.get(_commons_title_key(title), [])
        if len(matches) != 1:
            if len(matches) > 1:
                result["status"] = "ambiguous_commons_page"
            results.append(result)
            continue
        page = matches[0]
        if "missing" in page:
            result["status"] = "missing_file_page"
            results.append(result)
            continue
        imageinfo = (page.get("imageinfo") or [{}])[0]
        if not imageinfo:
            result["status"] = "missing_imageinfo"
            results.append(result)
            continue
        ext = imageinfo.get("extmetadata") or {}
        license_name = _metadata_value(ext, "LicenseShortName") or _metadata_value(ext, "License")
        observed_kind = classify_license(license_name)
        if observed_kind == candidate["license_kind"]:
            status = "license_match"
        elif candidate["license_kind"] == "CC-PD-MARK" and observed_kind == "PUBLIC-DOMAIN":
            status = "public_domain_review"
        else:
            status = "license_mismatch"
        result.update({
            "commons_title": page.get("title", title),
            "file_page_url": "https://commons.wikimedia.org/wiki/" + quote(
                str(page.get("title", title)).replace(" ", "_"), safe="/:()!$&'*,;=@-._~"
            ),
            "commons_license": license_name,
            "commons_license_url": _metadata_value(ext, "LicenseUrl"),
            "attribution_required": _metadata_value(ext, "AttributionRequired"),
            "artist": _metadata_value(ext, "Artist"),
            "credit": _metadata_value(ext, "Credit"),
            "image_url": imageinfo.get("url", ""),
            "sha1": imageinfo.get("sha1", ""),
            "thumbnail_url": imageinfo.get("thumburl", ""),
            "thumbnail_width": imageinfo.get("thumbwidth"),
            "thumbnail_height": imageinfo.get("thumbheight"),
            "status": status,
        })
        results.append(result)
    return results


def fetch_commons_metadata(candidates, delay=1.0, batch_size=20, opener=urlopen):
    if not 1 <= batch_size <= 50:
        raise ValueError("Commons batch_size must be between 1 and 50")
    results = []
    for start in range(0, len(candidates), batch_size):
        batch = candidates[start:start + batch_size]
        titles = list(dict.fromkeys(
            _commons_title_key(title) for title in (commons_title(item["source_url"]) for item in batch) if title
        ))
        params = urlencode({
            "action": "query",
            "format": "json",
            "prop": "imageinfo",
            "redirects": 1,
            "iiprop": "extmetadata|url|sha1",
            "iiurlwidth": 1024,
            "iiextmetadatafilter": "LicenseShortName|LicenseUrl|AttributionRequired|Artist|Credit",
            "titles": "|".join(titles),
        })
        request = Request(
            f"{COMMONS_API}?{params}",
            headers={"User-Agent": "android-ai-gateway-viettravel-audit/1.0 (metadata-only)"},
        )
        payload = None
        for attempt in range(6):
            try:
                with opener(request, timeout=30) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                break
            except HTTPError as error:
                if error.code not in {429, 500, 502, 503, 504} or attempt == 5:
                    raise
                retry_after = error.headers.get("Retry-After")
                wait = float(retry_after) if retry_after and retry_after.isdigit() else min(60, 2 ** (attempt + 1))
                time.sleep(wait)
            except (URLError, TimeoutError):
                if attempt == 5:
                    raise
                time.sleep(min(60, 2 ** (attempt + 1)))
        results.extend(parse_commons_response(batch, payload))
        if delay > 0 and start + batch_size < len(candidates):
            time.sleep(delay)
    return results


def fetch_rows(dataset, config, split, page_size, delay, max_rows=None, opener=urlopen):
    offset = 0
    rows = []
    while True:
        request_size = page_size if max_rows is None else min(page_size, max_rows - len(rows))
        if request_size <= 0:
            break
        query = urlencode({
            "dataset": dataset,
            "config": config,
            "split": split,
            "offset": offset,
            "length": request_size,
        })
        request = Request(
            f"{BASE_URL}?{query}",
            headers={"User-Agent": "android-ai-gateway-metadata-audit/1.0"},
        )
        page = None
        for attempt in range(6):
            try:
                with opener(request, timeout=30) as response:
                    page = json.loads(response.read().decode("utf-8"))
                break
            except HTTPError as error:
                if error.code not in {429, 500, 502, 503, 504} or attempt == 5:
                    raise
                retry_after = error.headers.get("Retry-After")
                wait = float(retry_after) if retry_after and retry_after.isdigit() else min(60, 2 ** (attempt + 1))
                time.sleep(wait)
            except (URLError, TimeoutError):
                if attempt == 5:
                    raise
                time.sleep(min(60, 2 ** (attempt + 1)))
        batch = [item.get("row", {}) for item in page.get("rows", [])]
        rows.extend(batch)
        if len(rows) and len(rows) % 1000 < len(batch):
            print(f"{split}: scanned {len(rows)} rows", flush=True)
        if len(batch) < request_size or (max_rows is not None and len(rows) >= max_rows):
            break
        offset += len(batch)
        if delay > 0:
            time.sleep(delay)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", default="phunguyendinhkh/VietTravelVQA")
    parser.add_argument("--config", default="default")
    parser.add_argument("--splits", nargs="+", default=("train", "test"))
    parser.add_argument("--page-size", type=int, default=100)
    parser.add_argument("--delay", type=float, default=0.75, help="seconds between page requests")
    parser.add_argument("--max-rows", type=int, help="limit each split for a small connectivity smoke test")
    parser.add_argument("--verify-commons", action="store_true", help="check candidate file-page license/attribution metadata")
    parser.add_argument("--commons-delay", type=float, default=1.0)
    parser.add_argument("--output", type=Path, required=True, help="write aggregate JSON report")
    args = parser.parse_args()
    if not 1 <= args.page_size <= 100:
        parser.error("--page-size must be between 1 and 100")
    if args.delay < 0:
        parser.error("--delay cannot be negative")
    if args.max_rows is not None and args.max_rows <= 0:
        parser.error("--max-rows must be positive")
    if args.commons_delay < 0:
        parser.error("--commons-delay cannot be negative")

    rows_by_split = {}
    for split in args.splits:
        rows_by_split[split] = fetch_rows(args.dataset, args.config, split, args.page_size, args.delay, args.max_rows)
    aggregate = audit_rows(rows_by_split)
    candidates = aggregate.pop("candidate_source_urls")
    report = {
        "dataset": args.dataset,
        "config": args.config,
        "scanned_at_utc": datetime.now(timezone.utc).isoformat(),
        "partial_scan": args.max_rows is not None,
        "image_payloads_downloaded": 0,
        **aggregate,
    }
    if args.verify_commons:
        commons_rows = fetch_commons_metadata(candidates, delay=args.commons_delay)
        report["commons_metadata_requests_result_count"] = len(commons_rows)
        report["commons_verification_status_counts"] = dict(sorted(Counter(
            row["status"] for row in commons_rows
        ).items()))
        report["commons_candidates"] = commons_rows
    else:
        report["candidate_source_urls"] = candidates
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
