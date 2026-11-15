"""Explicit live opt-ins; failures stay failures when a provider is selected."""

import json
import os
from pathlib import Path
from datetime import datetime, timezone

import httpx
import pytest

from earthsync.platform_v1.models import Point
from earthsync.platform_v1.providers.gfs import GfsForecast
from earthsync.platform_v1.providers.soil_webdav import SoilWebdav, MANIFEST_SHA256
from earthsync.platform_v1.providers.transport import Transport


def selected(name):
    return name in os.environ.get("EARTHSYNC_LIVE_PROVIDERS", "").split(",")


def receipt(name, result):
    path = os.getenv("EARTHSYNC_LIVE_7G_RECEIPTS")
    if path:
        out = Path(path)
        out.mkdir(parents=True, exist_ok=True)
        (out / (name + ".json")).write_text(json.dumps(result, indent=2) + "\n")


@pytest.mark.skipif(
    not selected("soil_webdav"), reason="Explicit soil_webdav live opt-in required"
)
async def test_live_accepted_isric_ph(store):
    async with httpx.AsyncClient(timeout=30) as client:
        result = await SoilWebdav(Transport(client), store).retrieve(
            Point(latitude=42.0308, longitude=-93.6319)
        )
    assert not result["cache_hit"]
    assert result["manifest_sha256"] == MANIFEST_SHA256
    assert len(result["cells"]) == 25 and any(
        c["value"] is None for c in result["cells"]
    )
    assert next(c for c in result["cells"] if c["at_query_point"])["value"] == 6.6
    assert result["uncertainty"] is None and not result["usable_for_assessment"]
    receipt("soil-webdav-fresh-live", result)


@pytest.mark.skipif(not selected("gfs"), reason="Explicit gfs live opt-in required")
async def test_live_official_gfs_run_and_valid_times(store):
    async with httpx.AsyncClient(timeout=30) as client:
        result = await GfsForecast(Transport(client), store).retrieve(
            Point(latitude=42.0308, longitude=-93.6319)
        )
    assert not result["cache_hit"]
    assert len(result["records"]) == 4
    assert result["issued_at"] is None and result["current_observed_weather"] is None
    assert result["official_warnings"] is None and not result["usable_for_assessment"]
    assert any(
        datetime.fromisoformat(r["valid_at"]) > datetime.now(timezone.utc)
        for r in result["records"]
    )
    assert all(
        r["temperature_c"] == r["raw_temperature_k"] - 273.15 for r in result["records"]
    )
    receipt("gfs-fresh-live", result)
