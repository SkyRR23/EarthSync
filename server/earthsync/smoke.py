"""Explicit live test. Writes an example only after successful real retrieval."""

import argparse
import asyncio
from pathlib import Path

import httpx

from .models import SeasonQuery
from .power import PowerProvider, ProviderError


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    query = SeasonQuery(
        latitude=16.85,
        longitude=96.15,
        start_year=2024,
        start_month=2,
        end_year=2024,
        end_month=2,
    )
    async with httpx.AsyncClient(
        timeout=httpx.Timeout(20, connect=5), follow_redirects=False
    ) as client:
        try:
            result = await PowerProvider(client).season(query)
        except ProviderError as exc:
            raise SystemExit(
                f"Live smoke failed: {exc.code}; no example written."
            ) from None
    if not all(
        row.rainfall_complete and row.temperature_complete
        for row in result.environment.seasonal.observations
    ):
        raise SystemExit(
            "Live response has incomplete coverage; no complete example written."
        )
    args.output.write_text(result.model_dump_json(indent=2) + "\n", encoding="utf-8")
    print("Real NASA POWER example written with retrieval metadata.")


if __name__ == "__main__":
    asyncio.run(main())
