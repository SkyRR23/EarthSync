import asyncio
from datetime import timedelta

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from earthsync.environmental.api import create_app
from earthsync.environmental.common import (
    Capture,
    RequestBudget,
    SourceCache,
    SourceError,
)
from earthsync.environmental.models import ContextQuery, Value
from earthsync.environmental.service import ContextService
from earthsync.environmental.soil import SoilGridsAdapter
from earthsync.environmental.vegetation import PRODUCTS, VegetationAdapter
from earthsync.environmental.weather import WeatherAdapter

from conftest import NOW


@pytest.mark.parametrize("kind", PRODUCTS)
async def test_missing_qa_never_admits_a_number(query, kind):
    evidence = await VegetationAdapter(kind).context(query)
    assert evidence.availability == "unavailable"
    assert evidence.reason == "MATCHING_QA_AND_PIXEL_SUPPORT_UNAVAILABLE"
    assert evidence.quality.qa_status == "missing"
    assert evidence.values == []


def test_api_defaults_honest_unavailability_and_no_climate_route(query):
    with TestClient(create_app()) as client:
        response = client.post("/api/environmental/v1/context", json=query.model_dump())
        assert response.status_code == 200
        assert response.headers["cache-control"] == "no-store"
        result = response.json()
        assert result["situation"]["agricultural_diagnosis"] is None
        assert result["situation"]["drainage"] is None
        assert result["situation"]["crop_recommendations"] is None
        assert result["query"]["target"]["field_id"] == "test-field"
        assert set(result["situation"]["availability"].values()) == {"unavailable"}
        assert result["evidence"][0]["reason"] == "PROVIDER_REST_SERVICE_PAUSED"
        assert result["evidence"][1]["reason"] == "LIVE_SOURCE_UNVERIFIED"
        assert (
            client.get("/api/environmental/v1/health").json()["upstream_checked"]
            is False
        )
        assert client.get("/api/v1/environment/season").status_code == 404
        assert (
            client.post(
                "/api/environmental/v1/context?latitude=0", json=query.model_dump()
            ).status_code
            == 422
        )


@pytest.mark.parametrize(
    "latitude,longitude", [(16.87, 96.2), (42, -93), (-33.9, 151.2), (0, 0), (80, 170)]
)
def test_global_selected_areas_keep_approximate_location_separate(latitude, longitude):
    query = {
        "schema_version": "environmental-context/1.0-proposal",
        "target": {
            "kind": "selected_area",
            "representative_point": {"latitude": latitude, "longitude": longitude},
        },
        "approximate_user_location": {"latitude": 0, "longitude": 0},
    }
    with TestClient(create_app()) as client:
        result = client.post("/api/environmental/v1/context", json=query)
        assert result.status_code == 200
        assert all(
            e["spatial_support"]["query_point"]
            == query["target"]["representative_point"]
            for e in result.json()["evidence"]
        )


@pytest.mark.parametrize(
    "mutate",
    [
        lambda q: q["target"].update(farmer_confirmed=False),
        lambda q: q["target"].update(farmer_confirmed="true"),
        lambda q: q["target"].update(boundary={"type": "Polygon"}),
        lambda q: q["target"]["point"].update(latitude=91),
        lambda q: q.update(timezone="Not/AZone"),
        lambda q: q.update(soil_depths=["0-5cm", "0-5cm"]),
        lambda q: q.update(schema_version="0.2-provisional"),
        lambda q: q.update(photo_location={"latitude": 1, "longitude": 2}),
    ],
)
def test_strict_contract_rejects_ambiguous_or_unsupported_inputs(query, mutate):
    payload = query.model_dump()
    mutate(payload)
    with TestClient(create_app()) as client:
        assert (
            client.post("/api/environmental/v1/context", json=payload).status_code
            == 422
        )


def test_area_point_mismatch_and_antimeridian():
    payload = {
        "schema_version": "environmental-context/1.0-proposal",
        "target": {
            "kind": "selected_area",
            "representative_point": {"latitude": 0, "longitude": 179},
            "bbox": [170, -5, -170, 5],
        },
    }
    assert ContextQuery.model_validate(payload).point.longitude == 179
    payload["target"]["representative_point"]["longitude"] = 0
    with pytest.raises(ValidationError):
        ContextQuery.model_validate(payload)


def test_missing_value_cannot_be_zero_or_present():
    with pytest.raises(ValidationError):
        Value(
            variable="clay",
            data_kind="modeled",
            statistic="mean",
            unit="%",
            scale=0.1,
            value=0,
            quality="missing",
        )


async def test_partial_service_source_failure_is_independent(query, soil_payload):
    def handler(request):
        if request.url.host == "rest.isric.org":
            return httpx.Response(
                200, json=soil_payload, headers={"etag": '"synthetic-rev-a"'}
            )
        raise httpx.ReadTimeout("synthetic timeout")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        service = ContextService(
            SoilGridsAdapter(http, probe=True, now=lambda: NOW),
            WeatherAdapter(http, probe=True, now=lambda: NOW),
            now=lambda: NOW,
        )
        result = await service.context(query)
    assert result.evidence[0].availability == "reference_only"
    assert result.evidence[0].retrieval.etag == '"synthetic-rev-a"'
    assert result.evidence[1].reason == "UPSTREAM_TIMEOUT"
    assert result.evidence[1].retrieval.retrieved_at is None
    assert result.situation.drainage is None
    assert all(e.spatial_support.scope == "regional_context" for e in result.evidence)


@pytest.mark.parametrize(
    "response,expected",
    [
        (httpx.Response(429), "UPSTREAM_HTTP_ERROR"),
        (httpx.Response(503), "UPSTREAM_HTTP_ERROR"),
        (
            httpx.Response(302, headers={"location": "https://other.invalid"}),
            "UPSTREAM_HTTP_ERROR",
        ),
        (httpx.Response(200, content="not json"), "INVALID_RESPONSE"),
        (httpx.Response(200, content=b"a" * 2_000_001), "RESPONSE_TOO_LARGE"),
        (
            httpx.Response(200, content=b'{"type":"Feature","type":"changed"}'),
            "INVALID_RESPONSE",
        ),
    ],
)
async def test_transport_failures_return_explicit_unavailable(
    query, response, expected
):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: response)
    ) as http:
        result = await SoilGridsAdapter(http, probe=True, now=lambda: NOW).context(
            query
        )
    assert result.availability == "unavailable" and result.reason == expected
    assert result.values == []


async def test_total_deadline_and_decoding_failure_are_unavailable(query, monkeypatch):
    from earthsync.environmental import common

    original_timeout = asyncio.timeout

    async def slow(request):
        await asyncio.sleep(1)
        return httpx.Response(200, json={})

    monkeypatch.setattr(common.asyncio, "timeout", lambda _: original_timeout(0))
    async with httpx.AsyncClient(transport=httpx.MockTransport(slow)) as http:
        result = await SoilGridsAdapter(http, probe=True).context(query)
        assert result.reason == "UPSTREAM_TIMEOUT"
    monkeypatch.setattr(common.asyncio, "timeout", original_timeout)

    def broken(request):
        raise httpx.DecodingError("synthetic invalid compressed body")

    async with httpx.AsyncClient(transport=httpx.MockTransport(broken)) as http:
        result = await SoilGridsAdapter(http, probe=True).context(query)
        assert result.reason == "UPSTREAM_TRANSPORT_UNAVAILABLE"


async def test_cache_exact_location_field_association_expiry_and_source_policy(
    query, soil_payload
):
    calls = []
    ticks = [0]

    def handler(request):
        calls.append(request)
        assert request.url.params.get_list("property")[0] == "phh2o"
        return httpx.Response(200, json=soil_payload)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        cache = SourceCache(ttl=10, capacity=1, clock=lambda: ticks[0])
        soil = SoilGridsAdapter(http, probe=True, now=lambda: NOW, cache=cache)
        first, second = await asyncio.gather(soil.context(query), soil.context(query))
        assert len(calls) == 1 and not first.cache_hit and second.cache_hit
        first.values[0].value = 999
        second = await soil.context(query)
        assert second.values[0].value == 6.3
        query.target.field_id = "different-field-same-point"
        assert (await soil.context(query)).cache_hit
        ticks[0] = 10
        assert not (await soil.context(query)).cache_hit
        assert len(calls) == 2
        query.target.point.longitude += 0.0000001
        assert not (await soil.context(query)).cache_hit
        assert len(calls) == 3 and len(cache.entries) == 1

        # Source/policy revision separates otherwise identical queries.
        async def revised():
            return second.model_copy(update={"cache_hit": False})

        assert not (await cache.get(("new-policy/2",), revised, lambda: NOW)).cache_hit


async def test_cache_does_not_store_failures_or_serve_expired_forecasts(
    query, soil_payload
):
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(503)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        soil = SoilGridsAdapter(http, probe=True)
        await soil.context(query)
        await soil.context(query)
        assert len(calls) == 2
    from earthsync.environmental.soil import read_soil
    from conftest import capture

    evidence = read_soil(capture(soil_payload), query)
    evidence.temporal_support.expires_at = NOW + timedelta(seconds=1)
    count = [0]

    async def load():
        count[0] += 1
        return evidence

    cache = SourceCache(ttl=1000, clock=lambda: 0)
    await cache.get(("test",), load, lambda: NOW)
    await cache.get(("test",), load, lambda: NOW + timedelta(seconds=1))
    assert count[0] == 2


def test_malformed_json_does_not_escape_as_a_success():
    from conftest import capture

    base = capture({})
    with pytest.raises(SourceError):
        Capture(b"[]", base.retrieval).json()
    with pytest.raises(SourceError):
        Capture(b'{"value":NaN}', base.retrieval).json()


def test_provider_budget_counts_attempts_and_releases_at_boundary():
    tick = [0]
    budget = RequestBudget(5, 60, clock=lambda: tick[0])
    assert all(budget.take() for _ in range(5))
    assert not budget.take()
    tick[0] = 60
    assert budget.take()
    assert len(budget.attempts) == 1


async def test_source_revision_refresh_keeps_original_hash_until_expiry(
    query, soil_payload
):
    tick = [0]
    revision = [1]

    def handler(request):
        soil_payload["properties"]["layers"][0]["depths"][0]["values"]["mean"] = (
            60 + revision[0]
        )
        return httpx.Response(
            200, json=soil_payload, headers={"etag": str(revision[0])}
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        soil = SoilGridsAdapter(
            http,
            probe=True,
            now=lambda: NOW,
            cache=SourceCache(ttl=10, clock=lambda: tick[0]),
        )
        first = await soil.context(query)
        revision[0] = 2
        cached = await soil.context(query)
        assert cached.retrieval.response_sha256 == first.retrieval.response_sha256
        assert cached.retrieval.etag == "1"
        tick[0] = 10
        updated = await soil.context(query)
        assert updated.retrieval.response_sha256 != first.retrieval.response_sha256
        assert updated.retrieval.etag == "2"
        assert updated.source.release is None


def test_api_serializes_partial_soil_and_independent_weather_failure(
    query, soil_payload
):
    def handler(request):
        return (
            httpx.Response(200, json=soil_payload)
            if request.url.host == "rest.isric.org"
            else httpx.Response(503)
        )

    http = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    service = ContextService(
        SoilGridsAdapter(http, probe=True, now=lambda: NOW),
        WeatherAdapter(http, probe=True, now=lambda: NOW),
        now=lambda: NOW,
    )
    try:
        with TestClient(create_app(service)) as client:
            soil_payload["properties"]["layers"].pop()
            response = client.post(
                "/api/environmental/v1/context", json=query.model_dump()
            )
            assert response.status_code == 200
            result = response.json()
            assert result["situation"]["availability"]["soil"] == "partial"
            assert result["situation"]["availability"]["weather"] == "unavailable"
            assert result["evidence"][0]["quality"]["missing"] == 4
            assert all(v["value"] is None for v in result["evidence"][0]["values"][-4:])
    finally:
        asyncio.run(http.aclose())
