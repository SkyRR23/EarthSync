"""Explicit live regional climate probes, never field ground-truth validation.

Public approximate locality points chosen as reproducible query examples; no
farm, crop-calendar or polygon applicability is asserted. Saves exact responses
and a dated receipt only when the caller runs this command with --allow-network.
"""

import argparse
import asyncio
import json
from pathlib import Path

import httpx

from earthsync.platform_v1.models import ClimateQuery, Point
from earthsync.platform_v1.providers.power_daily import PARAMETERS, ENDPOINT, read_daily
from earthsync.platform_v1.providers.transport import Transport

PILOTS = {
    "us_ia_story": (42.03, -93.62),
    "us_ks_tribune": (38.47, -101.75),
    "us_ar_stuttgart": (34.50, -91.55),
    "au_nsw_riverina": (-34.29, 146.05),
}


async def run(destination):
    destination.mkdir(mode=0o700, exist_ok=False)
    receipts = []
    async with httpx.AsyncClient(timeout=25) as client:
        transport = Transport(client)
        for pilot, (latitude, longitude) in PILOTS.items():
            query = ClimateQuery(
                point=Point(latitude=latitude, longitude=longitude),
                start="2024-02-01",
                end="2024-02-29",
            )
            for parameter in PARAMETERS:
                capture = await transport.get(
                    ENDPOINT,
                    {
                        "parameters": parameter,
                        "community": "AG",
                        "latitude": latitude,
                        "longitude": longitude,
                        "start": "20240201",
                        "end": "20240229",
                        "format": "JSON",
                        "time-standard": "LST",
                    },
                )
                record = read_daily(capture, query, parameter)
                name = f"{pilot}_{parameter}.real.json"
                (destination / name).write_bytes(capture.body)
                receipts.append(
                    {
                        "pilot": pilot,
                        "query_point": query.point.model_dump(),
                        "parameter": parameter,
                        "file": name,
                        "retrieved_at": capture.retrieved_at.isoformat(),
                        "response_sha256": capture.sha256,
                        "sources": record.source_metadata["header"]["sources"],
                        "days": len(record.measurements),
                        "missing_days": sum(
                            m.value is None for m in record.measurements
                        ),
                        "support": "regional model at approximate public locality example, not a confirmed farm",
                    }
                )
    (destination / "receipt.json").write_text(json.dumps(receipts, indent=2) + "\n")
    print(
        f"Captured {len(receipts)} real responses; no agricultural applicability claim"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--allow-network", action="store_true", required=True)
    args = parser.parse_args()
    asyncio.run(run(args.directory))


if __name__ == "__main__":
    main()
