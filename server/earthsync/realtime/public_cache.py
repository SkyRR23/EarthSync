"""Opt-in import of the hash-pinned PR #35 public Ames numeric receipts.

These are previously retrieved real point/cell observations, never a map, never
fresh by import, and never a substitute for a successful live-provider check.
"""

import hashlib
import json
from pathlib import Path
from urllib.parse import urlsplit

from .nasa import ASSET_HOSTS

SOURCE_SHA = "3e7d63d91fa081e8141f2d08ca842860be2d01be"
CAPTURE_SHA256 = "e97f73d19cd2a99159493042e1273d3a2c7b47a98b967a731ded33d17dcacbda"


def seed(repository, path=None):
    path = (
        path
        or Path(__file__).resolve().parents[3]
        / "docs/realtime/evidence/current-ames.json"
    )
    if not path.is_file():
        return 0
    raw = path.read_bytes().replace(b"\r\n", b"\n")
    if hashlib.sha256(raw).hexdigest() != CAPTURE_SHA256:
        return 0
    snapshot = json.loads(raw)
    if (
        snapshot["location"]["lat"] != 42.0308
        or snapshot["location"]["lon"] != -93.6319
    ):
        return 0
    count = 0
    for source, product in [
        ("imerg", "GPM_3IMERGHHE"),
        ("smap", "SPL4SMGP"),
        ("hls_ndvi", "HLSS30_VI"),
    ]:
        key = "source:ames:" + source
        if (repository.get(key) or {}).get("data"):
            continue
        previous = snapshot["sources"][source]
        data = previous.get("data")
        if (
            not data
            or data.get("numeric_observation") is not True
            or data.get("product") != product
        ):
            continue
        receipts = data.get("source_range_receipts", [])
        if not receipts or any(
            urlsplit(r["source_url"]).hostname not in ASSET_HOSTS
            or urlsplit(r["source_url"]).query
            for r in receipts
        ):
            continue
        repository.put(
            key,
            {
                "data": {
                    **data,
                    "cached_source_release": {
                        "git_sha": SOURCE_SHA,
                        "capture_sha256": CAPTURE_SHA256,
                        "classification": "CACHED_REAL_PUBLIC_AMES; original acquisition/retrieval times retained; point/cell only",
                    },
                },
                "error": "IMPORTED_VERIFIED_RELEASE_CACHE",
                "failures": 0,
                "next_check": 0,
                "last_success_at": previous["last_success_at"],
                "last_attempt_at": previous["last_attempt_at"],
            },
        )
        count += 1
    return count
