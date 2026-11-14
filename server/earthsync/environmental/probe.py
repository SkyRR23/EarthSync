"""Explicit live connectivity probe. Never enables a production adapter.

Exit 1 means at least one source remains unavailable. A successful HTTP call
would still not establish on-farm accuracy or scientific validation.
"""

import argparse
import asyncio
import json
from pathlib import Path

import httpx

from .common import utcnow
from .models import ContextQuery
from .service import ContextService
from .soil import SoilGridsAdapter
from .weather import WeatherAdapter


async def probe(args):
    query = ContextQuery.model_validate(
        {
            "schema_version": "environmental-context/1.0-proposal",
            "target": {
                "kind": "selected_area",
                "representative_point": {
                    "latitude": args.latitude,
                    "longitude": args.longitude,
                },
            },
            "timezone": args.timezone,
        }
    )
    async with httpx.AsyncClient(
        timeout=httpx.Timeout(20, connect=5), follow_redirects=False
    ) as client:
        service = ContextService(
            SoilGridsAdapter(client, probe=True), WeatherAdapter(client, probe=True)
        )
        result = await service.context(query)
    report = {
        "purpose": "live connectivity and metadata probe; not scientific validation",
        "checked_at_utc": utcnow().isoformat(),
        "result": result.model_dump(mode="json"),
    }
    # Avoid accidentally overwriting a previous retrieval record.
    with Path(args.output).open("x", encoding="utf-8") as output:
        json.dump(report, output, indent=2, allow_nan=False)
        output.write("\n")
    print(json.dumps({e.context_kind: e.reason for e in result.evidence}))
    return int(any(e.availability == "unavailable" for e in result.evidence))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--latitude", type=float, required=True)
    parser.add_argument("--longitude", type=float, required=True)
    parser.add_argument("--timezone", default="UTC")
    parser.add_argument("--output", required=True)
    return asyncio.run(probe(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
