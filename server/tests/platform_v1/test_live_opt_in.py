"""Real network acceptance tests. A blocked provider FAILS when selected."""

import os
from datetime import datetime, timezone

import httpx
import pytest

from earthsync.platform_v1.providers.discovery import DiscoveryQuery, HlsDiscovery
from earthsync.platform_v1.providers.power_daily import PowerDaily
from earthsync.platform_v1.providers.soil_wcs import SoilQuery, SoilWcs
from earthsync.platform_v1.providers.transport import Transport


def selected(provider):
    return provider in os.environ.get("EARTHSYNC_LIVE_PROVIDERS", "").split(",")


@pytest.mark.skipif(
    not selected("nasa"), reason="Explicit EARTHSYNC_LIVE_PROVIDERS=nasa required"
)
async def test_live_nasa_daily(query):
    async with httpx.AsyncClient(timeout=25) as client:
        result = await PowerDaily(Transport(client)).retrieve(query)
        assert result["gaps"] == [], result["gaps"]
        assert len(result["records"]) == 3
        assert all(len(r["measurements"]) == 29 for r in result["records"])


@pytest.mark.skipif(
    not selected("soil"), reason="Explicit EARTHSYNC_LIVE_PROVIDERS=soil required"
)
async def test_live_soil_wcs(query):
    async with httpx.AsyncClient(timeout=25) as client:
        result = await SoilWcs(Transport(client)).retrieve(SoilQuery(point=query.point))
        assert result.measurements[0].value is not None


@pytest.mark.skipif(
    not selected("hls"), reason="Explicit EARTHSYNC_LIVE_PROVIDERS=hls required"
)
async def test_live_hls_discovery(farm_input):
    async with httpx.AsyncClient(timeout=25) as client:
        result = await HlsDiscovery(Transport(client)).retrieve(
            DiscoveryQuery(
                farm=farm_input,
                start=datetime(2024, 7, 1, tzinfo=timezone.utc),
                end=datetime(2024, 7, 31, tzinfo=timezone.utc),
            )
        )
        assert result["records"]
