"""Opt-in bounded pH probe reusing the unchanged 7I WCS reader and transport.

Run with the existing server/requirements.lock environment. No REST fallback,
no provider retry, no automatic import, no field-observation promotion.
"""

import argparse
import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO / "server"))


async def probe(latitude, longitude, output):
    import httpx
    from earthsync.platform_v1.errors import PlatformError
    from earthsync.platform_v1.models import Point
    from earthsync.platform_v1.providers.soil_wcs import SoilQuery, SoilWcs
    from earthsync.platform_v1.providers.transport import Transport

    query = SoilQuery(point=Point(latitude=latitude, longitude=longitude))
    output.mkdir(parents=True, exist_ok=False)
    receipt = {
        "provider": "ISRIC SoilGrids WCS",
        "point_role": "public_regional_query_not_a_farm",
        "query": query.model_dump(),
        "started_at": datetime.now(timezone.utc).isoformat(),
        "captures": [],
        "review": "reference_only",
        "usable_for_assessment": False,
    }

    class RecordingTransport:
        def __init__(self, transport):
            self.transport = transport

        async def get(self, url, params):
            capture = await self.transport.get(url, params)
            filename = f"capture-{len(receipt['captures'])}.bin"
            (output / filename).write_bytes(capture.body)
            receipt["captures"].append(
                {
                    "url": url,
                    "params": params,
                    "file": filename,
                    "sha256": capture.sha256,
                    "bytes": len(capture.body),
                    "retrieved_at": capture.retrieved_at.isoformat(),
                    "headers": capture.headers,
                }
            )
            return capture

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            reader = SoilWcs(RecordingTransport(Transport(client)))
            evidence = await reader.retrieve(query)
            (output / "reference-evidence.json").write_text(
                evidence.model_dump_json(indent=2) + "\n", encoding="utf-8"
            )
        receipt["status"] = "parsed_reference_only_release_and_uncertainty_unverified"
    except PlatformError as error:
        receipt.update(status="unavailable", reason=error.code)
    receipt["completed_at"] = datetime.now(timezone.utc).isoformat()
    (output / "receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n", encoding="utf-8"
    )
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--latitude", type=float, required=True)
    parser.add_argument("--longitude", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = asyncio.run(probe(args.latitude, args.longitude, args.output))
    print(json.dumps(receipt))
    raise SystemExit(1 if receipt["status"] == "unavailable" else 0)
