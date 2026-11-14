"""Bounded, opt-in source capture. Never imports downloaded content or grants review."""

import argparse
from datetime import datetime, timezone
import hashlib
from http.client import HTTPException
import json
from pathlib import Path
import urllib.request


def fetch(url, maximum_bytes, opener=urllib.request.urlopen):
    request = urllib.request.Request(
        url, headers={"User-Agent": "EarthSync-reference-capture/1"}
    )
    with opener(request, timeout=30) as response:
        body = response.read(maximum_bytes + 1)
        length = response.headers.get("Content-Length")
        if len(body) > maximum_bytes:
            raise ValueError("download exceeds byte limit")
        if length is not None and int(length) != len(body):
            raise ValueError("truncated or inconsistent Content-Length")
        if not body:
            raise ValueError("empty response")
        return body, response.geturl(), dict(response.headers), response.status


def capture(plan, output):
    output.mkdir(parents=True, exist_ok=False)
    receipts = []
    for entry in plan:
        receipt = {
            "id": entry["id"],
            "url": entry["url"],
            "status": "unavailable",
            "request_started_at": datetime.now(timezone.utc).isoformat(),
            "retrieved_at": None,
            "sha256": None,
            "bytes": None,
            "file": None,
        }
        try:
            body, final_url, headers, status = fetch(
                entry["url"], entry["maximum_bytes"]
            )
            receipt["retrieved_at"] = datetime.now(timezone.utc).isoformat()
            # A 200 HTML challenge/error is not a dataset. Content review is still required.
            kind = entry["format"]
            if kind == "json":
                json.loads(body)
            elif kind == "pdf" and not body.startswith(b"%PDF-"):
                raise ValueError("invalid PDF signature")
            elif kind == "csv" and b"EcoPortCode,ScientificName," not in body[:200]:
                raise ValueError("unexpected ECOCROP CSV header")
            elif kind == "ecocrop_html" and (
                b"<h2>" not in body or b"Rainfall (annual)" not in body
            ):
                raise ValueError("not an ECOCROP data sheet")
            filename = entry["id"] + ".bin"
            (output / filename).write_bytes(body)
            receipt.update(
                status="captured_pending_content_review",
                sha256=hashlib.sha256(body).hexdigest(),
                bytes=len(body),
                file=filename,
                final_url=final_url,
                http_status=status,
                response_headers={
                    k: v
                    for k, v in headers.items()
                    if k.lower()
                    in {
                        "content-type",
                        "content-length",
                        "etag",
                        "last-modified",
                        "date",
                        "content-encoding",
                    }
                },
            )
        except (OSError, ValueError, HTTPException) as error:
            receipt["reason"] = str(error)
        receipts.append(receipt)
    (output / "receipts.json").write_text(
        json.dumps(receipts, indent=2) + "\n", encoding="utf-8"
    )
    return receipts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path)
    parser.add_argument(
        "output",
        type=Path,
        help="must be a new directory; local pending rights/content review",
    )
    parser.add_argument(
        "--source",
        action="append",
        help="capture only these source IDs; repeat for multiple IDs",
    )
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    if args.source:
        if set(args.source) - {s["id"] for s in plan}:
            parser.error("unknown source ID")
        plan = [s for s in plan if s["id"] in args.source]
    results = capture(plan, args.output)
    print(
        json.dumps(
            {
                "captured": sum(r["sha256"] is not None for r in results),
                "total": len(results),
            }
        )
    )
    raise SystemExit(0 if all(r["sha256"] for r in results) else 1)
