# ruff: noqa: E402  # Isolated harness resolves the unchanged baseline modules.
"""Bounded local native timings; no public-provider load test."""

import argparse
import asyncio
import hashlib
import json
import platform
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))
from earthsync.platform_v1.engine import RustEngine
from test_validation import weather


def distribution(values):
    ordered = sorted(values)
    return {
        "n": len(values),
        "minimum_seconds": min(values),
        "median_seconds": statistics.median(values),
        "p95_nearest_rank_seconds": ordered[
            __import__("math").ceil(0.95 * len(values)) - 1
        ],
        "maximum_seconds": max(values),
    }


async def main(engine_path):
    engine = RustEngine(
        str(engine_path), hashlib.sha256(engine_path.read_bytes()).hexdigest()
    )
    times = []
    for _ in range(20):
        start = time.perf_counter()
        result = await engine.water(
            dict(
                method="fao56-daily-pm.v1",
                latitude=20,
                elevation_m=100,
                day_basis="NASA_POWER_LST",
                days=[weather()],
            )
        )
        assert result["days"][0]["et0_mm"] is not None
        times.append(time.perf_counter() - start)
    receipts = json.loads(
        (ROOT / "docs/validation/evidence/provider-receipts.json").read_text()
    )
    report = {
        "release_sha": "660b479c3ffb714cd1d489e1241c026ceae6ed67",
        "hardware": platform.platform(),
        "native_sha256": engine.sha256,
        "local_native_subprocess_single_day": distribution(times),
        "real_network_transport_requests": distribution(
            [r["elapsed_seconds"] for r in receipts if "sha256" in r]
        ),
        "classification": "SYNTHETIC native timing inputs; REAL previously recorded network timings",
        "limits": "20 sequential native calls, no external extra load; not a concurrent capacity, Windows, mobile or production SLA measurement",
    }
    (ROOT / "docs/validation/evidence/performance.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", type=Path, required=True)
    asyncio.run(main(parser.parse_args().engine.resolve()))
