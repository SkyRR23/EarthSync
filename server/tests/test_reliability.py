"""Failure-boundary regressions. NASA transports here are independent mocks."""

import json
from pathlib import Path
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi.testclient import TestClient

from earthsync.api import create_app
from earthsync.models import SeasonQuery
from earthsync.power import PowerProvider, ProviderError
from earthsync.web_demo import create_demo_app
from test_backend import PARAMS


@pytest.mark.parametrize(
    "failure,code",
    [
        (httpx.ConnectError, "UPSTREAM_NETWORK_UNAVAILABLE"),
        (httpx.ReadTimeout, "UPSTREAM_TIMEOUT"),
    ],
)
async def test_transport_failures_are_distinct(failure, code):
    async def no_wait(seconds):
        pass

    def handler(request):
        raise failure("private URL and coordinates")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(ProviderError) as error:
            await PowerProvider(client, no_wait).season(SeasonQuery(**PARAMS))
    assert error.value.code == code


@pytest.mark.parametrize(
    "output",
    [
        b"not JSON",
        b'{"x":' * 1500 + b"0" + b"}" * 1500,
        b"[]",
        b"{}",
        b'{"status":"success","data":{}}',
        b'{"status":"error","error":{}}',
    ],
    ids=["not-json", "too-deep", "array", "empty", "bad-success", "bad-error"],
)
def test_wrong_engine_output_is_machine_readable(tmp_path, monkeypatch, output):
    executable = tmp_path / "engine"
    executable.touch()
    process = AsyncMock()
    process.communicate.return_value = (output, b"private stderr")
    process.returncode = 0
    monkeypatch.setattr(
        "earthsync.web_demo.asyncio.create_subprocess_exec",
        AsyncMock(return_value=process),
    )
    with TestClient(create_demo_app(engine=executable)) as client:
        response = client.post("/api/engine/integration", json={})
    assert response.status_code == 502
    assert response.json()["error"]["code"] == "ENGINE_INVALID_RESPONSE"
    assert "private" not in response.text


def test_engine_launch_failure_is_configuration_error(tmp_path, monkeypatch):
    executable = tmp_path / "engine.exe"
    executable.touch()
    monkeypatch.setattr(
        "earthsync.web_demo.asyncio.create_subprocess_exec",
        AsyncMock(side_effect=OSError("private executable path")),
    )
    with TestClient(create_demo_app(engine=executable)) as client:
        response = client.post("/api/engine/integration", json={})
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "ENGINE_CONFIGURATION"
    assert "private" not in response.text


def test_diagnostics_are_opt_in_and_health_does_not_fetch(monkeypatch):
    monkeypatch.delenv("EARTHSYNC_DIAGNOSTICS", raising=False)
    provider = AsyncMock()
    with TestClient(create_app(provider)) as client:
        assert client.get("/api/v1/health").json()["upstream_checked"] is False
        assert client.post("/api/v1/diagnostics/nasa").status_code == 404
    provider.season.assert_not_awaited()


def test_diagnostic_bypasses_cache_and_redacts_private_inputs(monkeypatch):
    monkeypatch.setenv("EARTHSYNC_DIAGNOSTICS", "1")
    provider = AsyncMock()
    provider.season.side_effect = ProviderError("UPSTREAM_SOURCE_CHANGED")
    with TestClient(create_app(provider)) as client:
        for _ in range(2):
            response = client.post("/api/v1/diagnostics/nasa")
            assert response.status_code == 502
            assert response.json()["error"]["code"] == "UPSTREAM_SOURCE_CHANGED"
            assert "96.15" not in response.text
        assert client.post("/api/v1/diagnostics/nasa?latitude=12").status_code == 422
    assert provider.season.await_count == 2


def test_captured_replay_through_real_http_engine():
    """Saved real evidence enters the compiled engine; no live NASA claim."""
    root = Path(__file__).parents[2]
    capture = json.loads((root / "server/examples/nasa_power_real.json").read_text())
    request = json.loads(
        (root / "engine/tests/fixtures/synthetic_integration_request.json").read_text()
    )
    request.update(
        data_mode="supplied_data",
        environment=capture["environment"],
        crop_references={"sources": [], "profiles": []},
        scenarios=[],
    )
    request["field"].update(
        latitude=capture["environment"]["latitude"],
        longitude=capture["environment"]["longitude"],
    )
    with TestClient(create_demo_app()) as client:
        response = client.post("/api/engine/integration", json=request)
    assert response.status_code == 200
    result = response.json()["data"]
    assert result["data_mode"] == "supplied_data"
    assert result["climate"]["rainfall_total_mm"] == pytest.approx(0.04)
    assert result["climate"][
        "calendar_day_weighted_mean_temperature_c"
    ] == pytest.approx(28.03655172413793)
    assert not result["rotations"]["scenarios"]


def test_nonzero_rust_exit_is_not_replaced(tmp_path, monkeypatch):
    executable = tmp_path / "engine"
    executable.touch()
    process = AsyncMock()
    process.communicate.return_value = (b'{"status":"success"}', b"private panic")
    process.returncode = 101
    monkeypatch.setattr(
        "earthsync.web_demo.asyncio.create_subprocess_exec",
        AsyncMock(return_value=process),
    )
    with TestClient(create_demo_app(engine=executable)) as client:
        response = client.post("/api/engine/integration", json={})
    assert response.status_code == 502
    assert response.json()["error"]["code"] == "ENGINE_FAILED"
    assert "private" not in response.text


def test_diagnostic_replayed_raw_capture_executes_rust(monkeypatch):
    """Injected NASA wire capture + real Rust, explicitly offline test only."""
    monkeypatch.setenv("EARTHSYNC_DIAGNOSTICS", "1")
    raw = (
        Path(__file__).parent / "fixtures/nasa_power_yangon_202402_live.json"
    ).read_bytes()
    calls = []

    def handler(request):
        calls.append(request)
        assert request.url.params["start"] == "20240201"
        return httpx.Response(200, content=raw)

    # AsyncClient is closed explicitly on the TestClient event loop.
    upstream = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    with TestClient(create_demo_app(provider=PowerProvider(upstream))) as client:
        for _ in range(2):
            response = client.post("/api/v1/diagnostics/integration")
            assert response.status_code == 200
            data = response.json()
            assert data["schema_version"] == "1.0-diagnostic"
            assert data["checks"]["rust_execution"] == "passed"
            assert len(data["engine_sha256"]) == 64
            assert data["cache_used"] is False
            assert "latitude" not in response.text
            assert "retrieved_at" not in response.text
        client.portal.call(upstream.aclose)
    assert len(calls) == 2


def test_missing_coverage_is_an_explicit_diagnostic_failure(monkeypatch):
    monkeypatch.setenv("EARTHSYNC_DIAGNOSTICS", "1")
    from test_backend import run, nasa

    class Incomplete:
        async def season(self, query):
            def handler(request):
                payload = nasa(request)
                payload["properties"]["parameter"]["T2M"] = {}
                return httpx.Response(200, json=payload)

            return await run(handler, query)

    with TestClient(create_demo_app(provider=Incomplete())) as client:
        response = client.post("/api/v1/diagnostics/integration")
        assert response.status_code == 502
        assert response.json()["error"]["code"] == "MISSING_DATA"


async def test_failed_requests_are_not_cached():
    from earthsync.api import SeasonCache

    provider = AsyncMock()
    provider.season.side_effect = ProviderError("UPSTREAM_NETWORK_UNAVAILABLE", True)
    cache = SeasonCache()
    for _ in range(2):
        with pytest.raises(ProviderError):
            await cache.get(SeasonQuery(**PARAMS), provider)
    assert provider.season.await_count == 2
    assert not cache.entries


@pytest.mark.parametrize(
    "latitude,longitude", [(0, 0), (-33.87, 151.21), (42.03, -93.62), (90, 180)]
)
async def test_global_coordinate_transport(latitude, longitude):
    from test_backend import nasa

    query = SeasonQuery(**(PARAMS | dict(latitude=latitude, longitude=longitude)))

    def handler(request):
        assert float(request.url.params["latitude"]) == latitude
        assert float(request.url.params["longitude"]) == longitude
        return httpx.Response(200, json=nasa(request))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as upstream:
        result = await PowerProvider(upstream).season(query)
    assert result.environment.latitude == latitude
    assert result.environment.longitude == longitude


async def test_whole_provider_deadline_includes_streaming(monkeypatch):
    import asyncio

    original = asyncio.timeout
    monkeypatch.setattr("earthsync.power.asyncio.timeout", lambda seconds: original(0))

    async def handler(request):
        await asyncio.Event().wait()

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as upstream:
        with pytest.raises(ProviderError) as error:
            await PowerProvider(upstream).season(SeasonQuery(**PARAMS))
    assert error.value.code == "UPSTREAM_TIMEOUT"


def test_api_deadline_includes_cache_queue(monkeypatch):
    import asyncio

    original = asyncio.timeout
    monkeypatch.setattr("earthsync.api.asyncio.timeout", lambda seconds: original(0))

    class Waiting:
        async def get(self, query, provider):
            await asyncio.Event().wait()

    with TestClient(create_app(cache=Waiting())) as client:
        response = client.get("/api/v1/environment/season", params=PARAMS)
    assert response.status_code == 504
    assert response.json()["error"]["code"] == "BACKEND_TIMEOUT"


def test_rust_queue_is_bounded(monkeypatch):
    async def busy(coroutine, seconds):
        coroutine.close()
        assert seconds == 5
        raise TimeoutError

    monkeypatch.setattr("earthsync.web_demo.asyncio.wait_for", busy)
    launch = AsyncMock()
    monkeypatch.setattr("earthsync.web_demo.asyncio.create_subprocess_exec", launch)
    with TestClient(create_demo_app()) as client:
        response = client.post("/api/engine/integration", json={})
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "ENGINE_BUSY"
    launch.assert_not_awaited()


async def test_real_recent_geosit_capture_is_never_relabeled():
    raw = (
        Path(__file__).parent / "fixtures/nasa_power_iowa_202610_geosit_live.json"
    ).read_bytes()
    payload = json.loads(raw)
    assert payload["header"]["sources"] == ["GEOSIT"]
    query = SeasonQuery(
        latitude=42.03,
        longitude=-93.62,
        start_year=2026,
        start_month=10,
        end_year=2026,
        end_month=10,
    )
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda req: httpx.Response(200, content=raw))
    ) as upstream:
        with pytest.raises(ProviderError) as error:
            await PowerProvider(upstream).season(query)
    assert error.value.code == "UPSTREAM_SOURCE_CHANGED"


def test_deep_request_json_is_a_structured_error():
    with TestClient(create_demo_app()) as client:
        response = client.post(
            "/api/engine/integration", content=b'{"x":' * 1500 + b"0" + b"}" * 1500
        )
    # Python parser depth limits differ across builds; Rust may reject first.
    assert response.status_code in (200, 422)
    assert response.json()["status"] == "error"
    assert response.json()["error"]["code"] in ("INVALID_INPUT", "INVALID_JSON")


async def test_chunked_provider_response_is_parsed_after_complete_body():
    raw = (
        Path(__file__).parent / "fixtures/nasa_power_yangon_202402_live.json"
    ).read_bytes()

    class Chunks(httpx.AsyncByteStream):
        async def __aiter__(self):
            for index in range(0, len(raw), 37):
                yield raw[index : index + 37]

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda request: httpx.Response(200, stream=Chunks())
        )
    ) as upstream:
        result = await PowerProvider(upstream).season(
            SeasonQuery(
                latitude=16.85,
                longitude=96.15,
                start_year=2024,
                start_month=2,
                end_year=2024,
                end_month=2,
            )
        )
    assert result.environment.seasonal.observations[0].rainfall_mm == pytest.approx(
        0.04
    )
