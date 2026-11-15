"""Synthetic selection-only fixtures; no live NASA claims."""

from types import SimpleNamespace

import pytest

from earthsync.realtime import ndvi
from earthsync.realtime.http import SourceError


@pytest.mark.parametrize(
    "preference,expected", [("latest", "newest"), ("clearest", "clearer")]
)
def test_preference_selects_one_dated_acquisition_without_compositing(
    monkeypatch, preference, expected
):
    products = [
        {
            "granule_id": "newest",
            "acquired_start": "2026-10-25T00:00:00Z",
            "coverage": 0.22,
        },
        {
            "granule_id": "partial",
            "acquired_start": "2026-10-23T00:00:00Z",
            "coverage": 71,
        },
        {
            "granule_id": "clearer",
            "acquired_start": "2026-10-22T00:00:00Z",
            "coverage": 95,
        },
    ]
    session = SimpleNamespace(downloaded=0, close=lambda: None)
    monkeypatch.setattr(ndvi, "AssetSession", lambda cancel: session)

    def window(product, geom, session, **kwargs):
        session.downloaded += 1024
        return {
            "granule_id": product["granule_id"],
            "acquired_at": product["acquired_start"],
            "coverage_pct": product["coverage"],
            "valid_pixels": int(product["coverage"] * 100),
        }

    monkeypatch.setattr(ndvi, "hls_window", window)
    service = ndvi.NdviOverlays(SimpleNamespace(repository=None))
    result = service._extract(products, {}, preference)
    selected = next(p for p in products if p["granule_id"] == expected)
    assert result["granule_id"] == expected
    assert result["acquired_at"] == selected["acquired_start"]
    assert result["coverage_pct"] == selected["coverage"]
    assert len(result["examined_candidate_ids"]) == (1 if preference == "latest" else 3)


def test_bounded_clearer_search_can_keep_already_verified_acquisition(monkeypatch):
    session = SimpleNamespace(downloaded=0, close=lambda: None)
    monkeypatch.setattr(ndvi, "AssetSession", lambda cancel: session)

    def window(product, geom, session, **kwargs):
        if product["granule_id"] == "timeout":
            raise SourceError("PROVIDER_TIMEOUT")
        return {
            "coverage_pct": 70,
            "valid_pixels": 700,
            "granule_id": "verified",
            "acquired_at": "2026-10-22T00:00:00Z",
        }

    monkeypatch.setattr(ndvi, "hls_window", window)
    service = ndvi.NdviOverlays(SimpleNamespace(repository=None))
    result = service._extract(
        [{"granule_id": "verified"}, {"granule_id": "timeout"}], {}, "clearest"
    )
    assert result["granule_id"] == "verified"
    assert result["coverage_pct"] == 70
    assert "Bounded search stopped" in result["selection_note"]


def test_acquisition_preferences_use_separate_cache_keys():
    service = ndvi.NdviOverlays(SimpleNamespace(repository=None))
    location = {"lat": 42.0308, "lon": -93.6319}
    assert service.key(location)[0] == service.key(location, preference="latest")[0]
    assert service.key(location)[0] != service.key(location, preference="clearest")[0]
