import asyncio
import copy
import json
from datetime import date, timedelta
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from earthsync.api import SeasonCache, create_app
from earthsync.models import SeasonQuery, SeasonResponse
from earthsync.power import PowerProvider, ProviderError

FIXTURE = json.loads(
    (Path(__file__).parent / "fixtures/nasa_daily_mock.json").read_text()
)
PARAMS = dict(
    latitude=16.85,
    longitude=96.15,
    start_year=2023,
    start_month=11,
    end_year=2024,
    end_month=2,
)


def nasa(request):
    payload = copy.deepcopy(FIXTURE)
    start = date.fromisoformat(
        str(request.url.params["start"])[:4]
        + "-"
        + str(request.url.params["start"])[4:6]
        + "-"
        + str(request.url.params["start"])[6:]
    )
    end = date.fromisoformat(
        str(request.url.params["end"])[:4]
        + "-"
        + str(request.url.params["end"])[4:6]
        + "-"
        + str(request.url.params["end"])[6:]
    )
    while start <= end:
        key = start.strftime("%Y%m%d")
        payload["properties"]["parameter"]["T2M"][key] = -2.0
        payload["properties"]["parameter"]["PRECTOTCORR"][key] = 2.0
        start += timedelta(days=1)
    return payload


async def run(handler, query=None, sleep=asyncio.sleep):
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        return await PowerProvider(client, sleep).season(query or SeasonQuery(**PARAMS))


async def test_cross_year_leap_and_json():
    result = await run(lambda req: httpx.Response(200, json=nasa(req)))
    rows = result.environment.seasonal.observations
    assert [r.rainfall_mm for r in rows] == [60, 62, 62, 58]
    assert all(
        r.mean_temperature_c == pytest.approx(-2) and r.temperature_complete
        for r in rows
    )
    assert result.environment.latitude == 16.85
    assert len(result.provenance["source_requests"]) == 2
    assert result.provenance["data_kind"] == "modeled"
    assert SeasonResponse.model_validate_json(result.model_dump_json()) == result


@pytest.mark.parametrize("bad", [-999, None, -1, "bad", True, float("inf")])
async def test_independent_missingness(bad):
    def handler(req):
        payload = nasa(req)
        if "20240201" in payload["properties"]["parameter"]["T2M"]:
            payload["properties"]["parameter"]["PRECTOTCORR"]["20240201"] = bad
        # httpx JSON intentionally forbids nonfinite floats; use a raw mock wire body.
        return httpx.Response(200, content=json.dumps(payload))

    result = await run(handler)
    last = result.environment.seasonal.observations[-1]
    assert last.rainfall_mm is None and not last.rainfall_complete
    assert last.temperature_complete and last.mean_temperature_c == pytest.approx(-2)
    assert result.provenance["coverage"][-1]["missing_or_invalid_dates"][
        "PRECTOTCORR"
    ] == ["20240201"]


async def test_absent_month_and_zero():
    def handler(req):
        payload = nasa(req)
        for var in payload["properties"]["parameter"].values():
            for key in list(var):
                if key.startswith("202402"):
                    del var[key]
                else:
                    var[key] = 0
        return httpx.Response(200, json=payload)

    rows = (await run(handler)).environment.seasonal.observations
    assert rows[0].rainfall_mm == 0 and rows[0].rainfall_complete
    assert rows[-1].mean_temperature_c is None and not rows[-1].temperature_complete


@pytest.mark.parametrize(
    "updates",
    [
        dict(latitude=float("nan")),
        dict(longitude=181),
        dict(start_month=0),
        dict(start_year=2025),
        dict(end_year=2027),
        dict(start_year=1980),
        dict(end_year=2026, end_month=11),
        dict(start_year=2020),
        dict(latitude=float("inf")),
    ],
)
def test_invalid_query(updates):
    with pytest.raises(ValidationError):
        SeasonQuery(**(PARAMS | updates))


@pytest.mark.parametrize("status", [429, 500, 502, 503, 504, "timeout"])
async def test_bounded_retries(status):
    calls, waits = [], []

    def handler(req):
        calls.append(req)
        if status == "timeout":
            raise httpx.ReadTimeout("private upstream detail")
        return httpx.Response(status, text="private upstream detail")

    async def sleep(seconds):
        waits.append(seconds)

    with pytest.raises(ProviderError) as err:
        await run(handler, sleep=sleep)
    assert err.value.retryable
    assert len(calls) == 3 and waits == [0.25, 0.5]


@pytest.mark.parametrize(
    "case", ["units", "time", "malformed", "missing", "rejected", "overflow"]
)
async def test_source_errors(case):
    calls = []

    def handler(req):
        calls.append(req)
        payload = nasa(req)
        if case == "units":
            payload["parameters"]["PRECTOTCORR"]["units"] = "mm"
        if case == "time":
            payload["header"]["time_standard"] = "UTC"
        if case == "missing":
            del payload["properties"]
        if case == "overflow":
            payload["properties"]["parameter"]["PRECTOTCORR"] = {
                k: 1e308 for k in payload["properties"]["parameter"]["PRECTOTCORR"]
            }
        return httpx.Response(
            400 if case == "rejected" else 200,
            content=b"private invalid json"
            if case == "malformed"
            else json.dumps(payload).encode(),
        )

    with pytest.raises(ProviderError):
        await run(handler)
    assert len(calls) <= 2  # Overflow is detected after both annual responses.


async def test_cache_ttl_eviction_and_copy():
    now = [0]
    cache = SeasonCache(ttl=10, capacity=1, clock=lambda: now[0])
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda req: httpx.Response(200, json=nasa(req)))
    ) as client:
        provider = PowerProvider(client)
        query = SeasonQuery(**PARAMS)
        first = await cache.get(query, provider)
        first.provenance.clear()
        cached = await cache.get(query, provider)
        assert cached.cache["hit"] and cached.provenance
        now[0] = 11
        assert not (await cache.get(query, provider)).cache["hit"]
        await cache.get(SeasonQuery(**(PARAMS | dict(latitude=17))), provider)
        assert len(cache.entries) == 1
        assert not (await cache.get(query, provider)).cache["hit"]


def test_api_health_validation_and_errors():
    class Broken:
        async def season(self, query):
            raise ProviderError("UPSTREAM_UNAVAILABLE", True)

    with TestClient(create_app(Broken())) as client:
        assert client.get("/api/v1/health").json()["upstream_checked"] is False
        for params in [
            PARAMS | dict(latitude="nan"),
            PARAMS | dict(end_year=2027),
            PARAMS | dict(extra="ignored"),
            {},
            list(PARAMS.items()) + [("latitude", 1)],
        ]:
            response = client.get("/api/v1/environment/season", params=params)
            assert response.status_code == 422
            assert response.json()["error"]["code"] == "INVALID_INPUT"
        for _ in range(2):
            response = client.get("/api/v1/environment/season", params=PARAMS)
            assert response.status_code == 503
            assert response.json()["error"]["retryable"]
            assert "private" not in response.text


def test_api_success_and_openapi():
    class Mock:
        async def season(self, query):
            return await run(lambda req: httpx.Response(200, json=nasa(req)), query)

    with TestClient(create_app(Mock())) as client:
        response = client.get("/api/v1/environment/season", params=PARAMS)
        assert response.status_code == 200
        data = response.json()
        assert data["environment"]["seasonal"]["metadata"]["rainfall_unit"] == "mm"
        assert client.get("/api/v1/environment/season", params=PARAMS).json()["cache"][
            "hit"
        ]
        assert (
            "/api/v1/environment/season" in client.get("/openapi.json").json()["paths"]
        )


async def test_real_rust_json_boundary(tmp_path):
    """Compile an external consumer without changing any engine files."""
    import os
    import shutil
    import subprocess

    cargo = shutil.which("cargo")
    if not cargo:
        pytest.skip("Rust must be activated to run the cross-language contract check")
    engine = Path(__file__).resolve().parents[2] / "engine"
    (tmp_path / "src").mkdir()
    (tmp_path / "Cargo.toml").write_text(
        '[package]\nname="backend_contract_check"\nversion="0.0.0"\nedition="2024"\n'
        "[dependencies]\nfield_shift_engine={path=" + json.dumps(str(engine)) + "}\n"
    )
    (tmp_path / "src/main.rs").write_text("""use std::io::{self, Read};
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    println!("{}", field_shift_engine::seasonal::analyze_season_json(&input).unwrap());
}""")
    data = await run(lambda req: httpx.Response(200, json=nasa(req)))
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = str(tmp_path / "target")
    proc = subprocess.run(
        [
            cargo,
            "run",
            "--quiet",
            "--offline",
            "--manifest-path",
            str(tmp_path / "Cargo.toml"),
        ],
        input=data.environment.seasonal.model_dump_json(),
        text=True,
        capture_output=True,
        env=env,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stderr
    summary = json.loads(proc.stdout)
    assert summary["rainfall_total_mm"] == 242
    assert summary["calendar_days"] == 121
    assert summary["metadata"]["data_kind"] == "modeled"


async def test_nonleap_temperature_gap_and_recovery():
    query = SeasonQuery(
        **(PARAMS | dict(start_year=2023, start_month=2, end_year=2023))
    )
    calls = []

    def handler(req):
        calls.append(req)
        if len(calls) == 1:
            return httpx.Response(503)
        payload = nasa(req)
        del payload["properties"]["parameter"]["T2M"]["20230228"]
        return httpx.Response(200, json=payload)

    async def no_wait(seconds):
        pass

    result = await run(handler, query, sleep=no_wait)
    row = result.environment.seasonal.observations[0]
    assert len(calls) == 2
    assert row.rainfall_mm == 56 and row.rainfall_complete
    assert row.mean_temperature_c is None and not row.temperature_complete
    assert result.provenance["coverage"][0]["expected_days"] == 28


async def test_concurrent_cache_misses_are_coalesced():
    calls = []

    class Mock:
        async def season(self, query):
            calls.append(query)
            await asyncio.sleep(0)
            return await run(lambda req: httpx.Response(200, json=nasa(req)), query)

    cache = SeasonCache()
    query = SeasonQuery(**PARAMS)
    results = await asyncio.gather(*(cache.get(query, Mock()) for _ in range(5)))
    assert len(calls) == 1
    assert sum(result.cache["hit"] for result in results) == 4
