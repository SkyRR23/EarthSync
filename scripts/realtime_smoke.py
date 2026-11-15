"""Real-provider smoke test at public references only; never injects fixtures.

PYTHONPATH=server python scripts/realtime_smoke.py --directory /private/new-run
Use a NEW private directory outside the checkout. Exit 1 means a mandatory
weather adapter did not pass. Metadata-only NASA access is never numeric success.
"""

import argparse
import asyncio
import json
import os
from pathlib import Path
import time

from earthsync.platform_v1.store import Store
from earthsync.realtime.service import REFERENCES, Realtime

ROOT = Path(__file__).resolve().parents[1]


async def run(args):
    directory = args.directory.absolute()
    if (
        directory.exists()
        or directory.resolve() != directory
        or ROOT == directory
        or ROOT in directory.parents
        or directory in ROOT.parents
    ):
        raise ValueError(
            "Use a new private directory outside the checkout, without symlinks"
        )
    directory.mkdir(mode=0o700, parents=True)
    service = Realtime(Store(directory))
    service.running = True
    if args.all_locations:
        for location in REFERENCES:
            service.activate(location["id"])
    result = {"classification": "ACTUAL_LIVE_PROVIDER_REQUESTS", "locations": {}}
    failed = False
    try:
        await service.tick()
        for location_id in sorted(service.active):
            started = time.perf_counter()
            snapshot = service.snapshot(location_id)
            duration = (time.perf_counter() - started) * 1000
            summary = {"cache_snapshot_ms": round(duration, 3), "sources": {}}
            for source_id, source in snapshot["sources"].items():
                data = source["data"] or {}
                summary["sources"][source_id] = {
                    k: source.get(k)
                    for k in (
                        "status",
                        "error",
                        "last_success_at",
                        "last_attempt_at",
                        "processing_ms",
                        "latency",
                        "message",
                    )
                }
                summary["sources"][source_id].update(
                    {
                        k: data[k]
                        for k in (
                            "observed_at",
                            "measurements",
                            "stations",
                            "issued_at",
                            "updated_at",
                            "office",
                            "valid_until",
                            "products",
                            "provenance",
                        )
                        if k in data
                    }
                )
                summary["sources"][source_id]["record_count"] = len(
                    data.get("hourly", data.get("alerts", []))
                )
                if source_id in (
                    "open_meteo",
                    "nws_forecast",
                    "nws_grid",
                    "nws_alerts",
                    "iowa_station",
                ) and source["status"] not in ("FRESH", "GEOGRAPHIC_NON_COVERAGE"):
                    failed = True
            result["locations"][location_id] = summary
        output = directory / "live-summary.json"
        output.write_text(
            json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        output.chmod(0o600)
        print(
            json.dumps(
                {
                    "summary": str(output),
                    "mandatory_weather": "FAIL" if failed else "PASS",
                    "locations": list(result["locations"]),
                }
            )
        )
    finally:
        await service.close()
    return int(failed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--all-locations", action="store_true")
    os.umask(0o077)
    raise SystemExit(asyncio.run(run(parser.parse_args())))
