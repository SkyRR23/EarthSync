"""Fetch source responses into a NEW audit directory, without changing the catalog.

Raw responses stay local for license review. A successful download is not reviewed
crop evidence. Failure writes an unavailable receipt and exits nonzero.
"""

import argparse
import concurrent.futures
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from catalog import ROOT, encoded, read_json, sha256

MAX_BYTES = 12 * 1024 * 1024
TIMEOUT_SECONDS = 25


def capture(source, output, opener=urlopen):
    receipt = {
        "source_id": source["id"],
        "requested_url": source["url"],
        "retrieved_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "state": "unavailable",
        "http_status": None,
        "final_url": None,
        "content_type": None,
        "provider_response_sha256": None,
        "bytes": None,
        "raw_path": None,
        "error": None,
        "review_status": "unreviewed",
        "recommendation_eligible": False,
    }
    try:
        request = Request(
            source["url"],
            headers={"User-Agent": "EarthSync-CropKnowledge/0.1 (source audit)"},
        )
        with opener(request, timeout=TIMEOUT_SECONDS) as response:
            receipt["http_status"] = response.status
            receipt["final_url"] = response.geturl()
            receipt["content_type"] = response.headers.get_content_type()
            if response.status != 200:
                raise ValueError("Source did not return HTTP 200")
            if receipt["content_type"] not in (
                "text/html",
                "application/pdf",
                "application/json",
                "text/plain",
            ):
                raise ValueError("Unexpected source content type")
            raw = response.read(MAX_BYTES + 1)
            if not raw or len(raw) > MAX_BYTES:
                raise ValueError("Empty or oversized source response")
            if receipt["content_type"] == "application/pdf" and not raw.startswith(
                b"%PDF-"
            ):
                raise ValueError("PDF content signature mismatch")
        # Exclusive writes preserve earlier captures. No source text is executed.
        path = output / (source["id"] + ".response")
        with path.open("xb") as stream:
            stream.write(raw)
        receipt.update(
            state="available_for_review",
            provider_response_sha256=sha256(raw),
            bytes=len(raw),
            raw_path=path.name,
        )
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
        if isinstance(error, HTTPError):
            receipt["http_status"] = error.code
        receipt["error"] = str(error)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New directory; existing directories are rejected",
    )
    parser.add_argument(
        "--source", action="append", help="Source ID; repeat for a subset"
    )
    args = parser.parse_args()
    sources = read_json(ROOT / "sources.json")
    selected = set(args.source or [s["id"] for s in sources])
    if not selected.issubset({s["id"] for s in sources}):
        parser.error("Unknown source ID")
    sources = [s for s in sources if s["id"] in selected]
    args.output.mkdir(parents=True, exist_ok=False)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        receipts = list(pool.map(lambda source: capture(source, args.output), sources))
    report = {
        "schema_version": "earthsync.source-fetch-audit.v1",
        "raw_reuse": "local_license_review_only",
        "sources": receipts,
    }
    (args.output / "receipts.json").write_bytes(encoded(report))
    available = sum(r["state"] == "available_for_review" for r in receipts)
    print(
        json.dumps(
            {
                "available_for_review": available,
                "unavailable": len(receipts) - available,
                "receipts": str(args.output / "receipts.json"),
            }
        )
    )
    raise SystemExit(0 if available == len(receipts) else 1)


if __name__ == "__main__":
    main()
