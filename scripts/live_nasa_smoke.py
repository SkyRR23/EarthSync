"""Opt-in authenticated NASA extraction; receipts contain public derived metadata only."""

import argparse
import asyncio
from datetime import datetime, timezone
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory

from earthsync.platform_v1.store import Store
from earthsync.realtime.ndvi import NdviOverlays, inspect_pixel
from earthsync.realtime.service import REFERENCES, Realtime


async def check(output, numeric):
    if not os.getenv("EARTHDATA_TOKEN"):
        raise RuntimeError("EARTHDATA_TOKEN is required for this explicitly live test")
    if output.exists():
        raise RuntimeError("Choose a new receipt filename")
    with TemporaryDirectory(prefix="earthsync-live-nasa-") as temporary:
        realtime = Realtime(Store(Path(temporary)), enabled=False)
        overlays = NdviOverlays(realtime)
        location = REFERENCES[0]
        report = {
            "classification": "ACTUAL_AUTHENTICATED_NASA; no mocked HTTP",
            "checked_at": datetime.now(timezone.utc).isoformat(),
            "location": "Ames public reference",
            "numeric": {},
        }
        try:
            overlays.request(location)
            await asyncio.wait_for(asyncio.gather(*overlays.tasks.values()), 240)
            snapshot = overlays.snapshot(location)
            data = snapshot["data"]
            report["overlay"] = {
                "status": snapshot["status"],
                "error": snapshot["error"],
            }
            if data:
                report["overlay"].update(
                    {
                        key: data.get(key)
                        for key in (
                            "product",
                            "version",
                            "granule_id",
                            "acquired_at",
                            "retrieved_at",
                            "resolution_m",
                            "quality",
                            "coverage_pct",
                            "valid_pixels",
                            "polygon_pixels",
                            "total_bytes_downloaded",
                            "qa_policy",
                        )
                    }
                )
                report["pixel"] = inspect_pixel(data, location["lat"], location["lon"])
            if numeric:
                for name in ("imerg", "smap", "hls_ndvi"):
                    await realtime.refresh("ames", name)
                    state = realtime.repository.get("source:ames:" + name)
                    value = state.get("data") or {}
                    report["numeric"][name] = {
                        "error": state.get("error"),
                        "acquired_at": value.get("acquired_start"),
                        "product": value.get("product"),
                        "measurements": value.get("measurements", []),
                    }
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(
                json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8"
            )
            if not data or not data["valid_pixels"]:
                raise RuntimeError(
                    "No QA-accepted live overlay; see the provider status in the receipt"
                )
            print(
                f"PASS authenticated native HLS-VI overlay: {data['valid_pixels']} accepted cells; {data['coverage_pct']}% coverage; acquired {data['acquired_at']}"
            )
            for name, value in report["numeric"].items():
                print(
                    f"NASA {name}: {value['error'] or 'accepted numeric source'}; acquired {value['acquired_at']}"
                )
        finally:
            await overlays.close()
            await realtime.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--numeric", action="store_true")
    args = parser.parse_args()
    asyncio.run(check(args.output, args.numeric))
