"""Synthetic provider transports test contracts; these are NOT live receipts."""

import asyncio
from datetime import datetime, timedelta, timezone

import httpx
import pytest

from earthsync.platform_v1.store import Store
from earthsync.realtime.http import CachedHttp, SourceError
from earthsync.realtime.providers import (
    IowaStation,
    NwsAlerts,
    NwsForecast,
    OpenMeteo,
    local_time,
)
from earthsync.realtime.service import REFERENCES, Realtime, Repository

NOW = datetime(2026, 11, 15, 12, 0, tzinfo=timezone.utc)


def iso(delta=0):
    return (NOW + timedelta(seconds=delta)).isoformat()


def fixture_response(request):
    url = str(request.url)
    if "/geojson/network.py" in url:
        return httpx.Response(
            200,
            json={
                "features": [
                    {
                        "id": sid,
                        "geometry": {"coordinates": [-93.65, 42.02]},
                        "properties": {"sname": sid + " test", "online": online},
                    }
                    for sid, online in (
                        ("AMFI4", True),
                        ("AHDI4", True),
                        ("OFFLINE", False),
                    )
                ]
            },
        )
    if "/request/isusm.py" in url:
        return httpx.Response(
            200,
            text="station,valid,tmpf,tmpf_f,relh,relh_f,precip,precip_f,speed,speed_f,soil12vwc,soil12vwc_f,sv_vwc14,sv_vwc14_f\nAMFI4,2026-11-15 11:59+00,14,,60,,0.1,,10,,30,,0.31,\nAHDI4,2026-11-15 11:58+00,99,R,55,,0,,5,,28,F,0.32,\n",
        )
    if "/points/" in url:
        return httpx.Response(
            200,
            json={
                "properties": {
                    "forecast": "https://api.weather.gov/gridpoints/DMX/1,2/forecast",
                    "forecastHourly": "https://api.weather.gov/gridpoints/DMX/1,2/forecast/hourly",
                    "forecastOffice": "https://api.weather.gov/offices/DMX",
                    "gridId": "DMX",
                    "timeZone": "America/Chicago",
                }
            },
        )
    if "/forecast" in url:
        return httpx.Response(
            200,
            json={
                "properties": {
                    "generatedAt": iso(-3600),
                    "updateTime": iso(-3600),
                    "periods": [
                        {
                            "startTime": iso(),
                            "endTime": iso(3600),
                            "temperature": 32,
                            "temperatureUnit": "F",
                            "probabilityOfPrecipitation": {"value": 25},
                            "relativeHumidity": {"value": 80},
                            "windSpeed": "5 mph",
                            "windDirection": "NW",
                            "shortForecast": "Test forecast",
                        }
                    ],
                }
            },
        )
    if "/alerts/active" in url:
        return httpx.Response(200, json={"type": "FeatureCollection", "features": []})
    if "/v1/forecast" in url:
        units = {
            "temperature_2m": "°C",
            "relative_humidity_2m": "%",
            "precipitation": "mm",
            "precipitation_probability": "%",
            "wind_speed_10m": "m/s",
            "soil_moisture_0_to_1cm": "m³/m³",
        }
        return httpx.Response(
            200,
            json={
                "hourly": {
                    "time": [NOW.timestamp()],
                    **{k: [0.3 if "soil" in k else 10] for k in units},
                },
                "hourly_units": units,
                "latitude": 42,
                "longitude": -93,
            },
        )
    raise AssertionError(url)


@pytest.fixture
def repository(tmp_path):
    return Repository(Store(tmp_path))


@pytest.mark.asyncio
async def test_station_units_qc_depth_distance_incremental(repository):
    calls = []

    def handle(request):
        calls.append(request)
        return fixture_response(request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        adapter = IowaStation(CachedHttp(client, repository, lambda: NOW.timestamp()))
        data = await adapter.fetch(REFERENCES[0], None, NOW)
        values = {
            (r["station_id"], r["variable"], r["depth_cm"]): r
            for r in data["measurements"]
        }
        assert values[("AMFI4", "air_temperature", None)]["value"] == -10
        assert values[("AMFI4", "rainfall", None)]["value"] == pytest.approx(2.54)
        assert values[("AMFI4", "wind_speed", None)]["value"] == pytest.approx(4.4704)
        assert values[("AMFI4", "soil_moisture", 30.48)]["value"] == 0.3
        assert values[("AMFI4", "soil_moisture_soilvue", 35.56)]["value"] == 0.31
        assert ("AHDI4", "air_temperature", None) not in values
        assert ("AHDI4", "soil_moisture", 30.48) not in values
        assert len(data["stations"]) == 2 and data["stations"][0]["distance_km"] > 0
        second = await adapter.fetch(REFERENCES[0], data, NOW + timedelta(minutes=1))
        assert len(second["records"]) == len(data["records"])
        assert calls[-1].url.params["timeres"] == "minute"
        assert calls[-1].url.params["sts"] == iso(-360)
        assert data["publication_at"] is None


def test_iowa_timezone_dst():
    assert local_time("2026-07-01T12:00:00Z", "America/Chicago").endswith("-05:00")
    assert local_time("2026-11-15T12:00:00Z", "America/Chicago").endswith("-06:00")


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "configured,error,expected",
    [
        (True, "AUTHENTICATION_REQUIRED", 1),
        (False, "AUTHENTICATION_REQUIRED", 0),
        (True, "AUTHORIZATION_DENIED", 1),
        (True, "PROVIDER_OUTAGE", 0),
    ],
)
async def test_new_credentials_retry_cached_auth_failure_once(
    tmp_path, monkeypatch, configured, error, expected
):
    if configured:
        monkeypatch.setenv("EARTHDATA_TOKEN", "SYNTHETIC_TEST_TOKEN")
    else:
        monkeypatch.delenv("EARTHDATA_TOKEN", raising=False)
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(fixture_response)
    ) as client:
        service = Realtime(
            Store(tmp_path), client=client, clock=lambda: NOW.timestamp()
        )
        calls = []

        class RejectedCredentials:
            interval = 900

            async def fetch(self, location, old, now):
                calls.append(location)
                raise SourceError("AUTHENTICATION_REQUIRED")

        service.adapters["imerg"] = RejectedCredentials()
        original = {"classification": "SYNTHETIC TEST", "observed_at": iso(-3600)}
        key = "source:ames:imerg"
        service.repository.put(
            key,
            {
                "data": original,
                "error": error,
                "failures": 2,
                "last_success_at": iso(-3600),
                "next_check": NOW.timestamp() + 7200,
            },
        )
        await service.refresh("ames", "imerg")
        await service.refresh("ames", "imerg")
        assert len(calls) == expected
        assert service.repository.get(key)["data"] == original


@pytest.mark.asyncio
async def test_conditional_get_and_provider_ttl(repository):
    epoch = [NOW.timestamp()]
    calls = []

    def handle(request):
        calls.append(request)
        if len(calls) == 1:
            return httpx.Response(
                200,
                json={"real": "synthetic test"},
                headers={"ETag": '"version1"', "Cache-Control": "public, max-age=120"},
            )
        assert request.headers["If-None-Match"] == '"version1"'
        return httpx.Response(304, headers={"Cache-Control": "max-age=180"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        transport = CachedHttp(client, repository, lambda: epoch[0])
        one = await transport.get("https://api.weather.gov/test", ttl=60)
        epoch[0] += 60
        assert (await transport.get("https://api.weather.gov/test", ttl=60))[
            "retrieved_at"
        ] == one["retrieved_at"]
        assert len(calls) == 1
        epoch[0] += 61
        two = await transport.get("https://api.weather.gov/test", ttl=60)
        assert two["sha256"] == one["sha256"] and two["http_status"] == 304
        assert two["next_check"] == epoch[0] + 180


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "status,code",
    [
        (401, "AUTHENTICATION_REQUIRED"),
        (403, "AUTHORIZATION_DENIED"),
        (429, "RATE_LIMIT"),
        (500, "PROVIDER_OUTAGE"),
        (503, "PROVIDER_OUTAGE"),
    ],
)
async def test_failure_backoff_retry_after(repository, status, code):
    calls = []

    def handle(request):
        calls.append(request)
        return httpx.Response(status, headers={"Retry-After": "300"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        transport = CachedHttp(client, repository, lambda: NOW.timestamp())
        with pytest.raises(SourceError, match=code):
            await transport.get("https://api.weather.gov/test", ttl=60)
        with pytest.raises(SourceError, match="PROVIDER_BACKOFF"):
            await transport.get("https://api.weather.gov/another", ttl=60)
        assert len(calls) == 1
        assert transport.blocked_until["api.weather.gov"] == NOW.timestamp() + 300
        restarted = CachedHttp(client, repository, lambda: NOW.timestamp())
        with pytest.raises(SourceError, match="PROVIDER_BACKOFF"):
            await restarted.get("https://api.weather.gov/after-restart", ttl=60)
        assert len(calls) == 1


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "exception,code",
    [
        (httpx.ConnectError("DNS failure"), "NETWORK_OR_TLS_ERROR"),
        (httpx.ConnectError("certificate verify failed"), "NETWORK_OR_TLS_ERROR"),
        (httpx.ReadTimeout("slow"), "PROVIDER_TIMEOUT"),
        (httpx.ProxyError("403"), "NETWORK_POLICY_OR_PROXY"),
    ],
)
async def test_network_failure_categories(repository, exception, code):
    def handle(request):
        raise exception

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        with pytest.raises(SourceError, match=code):
            await CachedHttp(client, repository).get(
                "https://api.weather.gov/test", ttl=60
            )


@pytest.mark.asyncio
async def test_host_allowlist_rejects_provider_redirect(repository):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda r: httpx.Response(
                302, headers={"location": "http://127.0.0.1/private"}
            )
        )
    ) as client:
        transport = CachedHttp(client, repository)
        with pytest.raises(SourceError, match="UNSUPPORTED_ENDPOINT"):
            await transport.get("https://attacker.invalid", ttl=60)
        with pytest.raises(SourceError, match="HTTP_ERROR"):
            await transport.get("https://api.weather.gov/test", ttl=60)


@pytest.mark.asyncio
async def test_nws_mapping_units_and_expired_filter(repository):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(fixture_response)
    ) as client:
        adapter = NwsForecast(CachedHttp(client, repository, lambda: NOW.timestamp()))
        data = await adapter.fetch(REFERENCES[0], None, NOW)
        assert data["hourly"][0]["temperature_c"] == 0
        assert data["daily"][0]["original_temperature_unit"] == "F"
        assert data["office"].endswith("DMX")
        assert data["publication_at"] is None
        with pytest.raises(SourceError, match="EXPIRED_DATA"):
            await adapter.fetch(REFERENCES[0], None, NOW + timedelta(days=2))


@pytest.mark.asyncio
async def test_alert_expiry_cancellation_and_identity(repository):
    def handle(request):
        if "/points/" in str(request.url):
            return fixture_response(request)
        return httpx.Response(
            200,
            json={
                "type": "FeatureCollection",
                "features": [
                    {
                        "id": "https://api.weather.gov/alerts/" + str(i),
                        "properties": {
                            "id": str(i),
                            "expires": iso(expiry),
                            "messageType": message,
                            "status": "Actual",
                            "senderName": "Official test issuer",
                            "severity": "Severe",
                        },
                    }
                    for i, expiry, message in (
                        (1, 3600, "Alert"),
                        (2, -1, "Alert"),
                        (3, 3600, "Cancel"),
                    )
                ],
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        adapter = NwsAlerts(CachedHttp(client, repository, lambda: NOW.timestamp()))
        data = await adapter.fetch(REFERENCES[0], None, NOW)
        assert [a["id"] for a in data["alerts"]] == ["1"]
        assert len(data["expired_or_cancelled"]) == 2
        with pytest.raises(SourceError, match="GEOGRAPHIC_NON_COVERAGE"):
            await adapter.fetch(REFERENCES[3], None, NOW)


@pytest.mark.asyncio
async def test_open_meteo_units_missingness_and_model_identity(repository):
    # Test dispatch must check Open-Meteo before the generic /forecast route.
    def handle(request):
        if request.url.host == "api.open-meteo.com":
            units = {
                "temperature_2m": "°C",
                "relative_humidity_2m": "%",
                "precipitation": "mm",
                "precipitation_probability": "%",
                "wind_speed_10m": "m/s",
                "soil_moisture_0_to_1cm": "m³/m³",
            }
            return httpx.Response(
                200,
                json={
                    "hourly": {
                        "time": [NOW.timestamp()],
                        **{k: [0.3 if "soil" in k else 10] for k in units},
                    },
                    "hourly_units": units,
                },
            )
        return fixture_response(request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        data = await OpenMeteo(
            CachedHttp(client, repository, lambda: NOW.timestamp())
        ).fetch(REFERENCES[3], None, NOW)
        assert data["hourly"][0]["soil_moisture_0_to_1cm"] == 0.3
        assert data["model_initialization_at"] is None


@pytest.mark.asyncio
async def test_empty_alert_feed_never_verifies_an_unmapped_field(repository):
    requests = []

    def handle(request):
        requests.append(str(request.url))
        return httpx.Response(404)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        adapter = NwsAlerts(CachedHttp(client, repository, lambda: NOW.timestamp()))
        with pytest.raises(SourceError, match="GEOGRAPHIC_NON_COVERAGE"):
            await adapter.fetch(REFERENCES[0], None, NOW)
    assert len(requests) == 1 and "/points/" in requests[0]


@pytest.mark.asyncio
async def test_restart_persistence_alert_failure_never_all_clear(repository):
    epoch, fail = [NOW.timestamp()], [False]

    def handle(request):
        if fail[0]:
            return httpx.Response(503)
        return fixture_response(request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        service = Realtime(repository.store, client=client, clock=lambda: epoch[0])
        service.running = True
        await service.refresh("ames", "nws_alerts")
        fresh = service.snapshot("ames")["sources"]["nws_alerts"]
        assert fresh["status"] == "FRESH" and fresh["message"].startswith(
            "No active official"
        )
        epoch[0] += 61
        fail[0] = True
        await service.refresh("ames", "nws_alerts")
        stale = service.snapshot("ames")["sources"]["nws_alerts"]
        assert stale["status"] == "CACHED_REAL_STALE"
        assert stale["message"] == "Official alert status could not be verified."
        assert stale["last_success_at"] == fresh["last_success_at"]
        restarted = Realtime(repository.store, client=client, clock=lambda: epoch[0])
        assert (
            restarted.snapshot("ames")["sources"]["nws_alerts"]["data"] == stale["data"]
        )
        assert restarted.snapshot("ames")["worker_running"] is False


@pytest.mark.asyncio
async def test_station_freshness_each_sensor_and_no_browser_fetch(repository):
    calls = []
    epoch = [NOW.timestamp()]

    def handle(request):
        calls.append(request)
        return fixture_response(request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
        service = Realtime(repository.store, client=client, clock=lambda: epoch[0])
        service.running = True
        await service.refresh("ames", "iowa_station")
        for _ in range(20):
            assert (
                service.snapshot("ames")["sources"]["iowa_station"]["status"] == "FRESH"
            )
        assert len(calls) == 2
        epoch[0] += 1000
        source = service.snapshot("ames")["sources"]["iowa_station"]
        assert source["status"] == "CACHED_REAL_STALE"
        assert all(
            m["status"] == "CACHED_REAL_STALE" for m in source["data"]["measurements"]
        )


@pytest.mark.asyncio
async def test_worker_automatic_update_and_graceful_shutdown(repository):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(fixture_response)
    ) as client:
        service = Realtime(repository.store, client=client)
        event = asyncio.Event()

        async def refresh(*args):
            event.set()

        service.refresh = refresh
        await service.start()
        await asyncio.wait_for(event.wait(), 1)
        await service.close()
        assert not service.running and service.task.done()


def test_bounded_cache_and_complete_backup_restore(repository, tmp_path):
    from earthsync.platform_v1.maintenance import backup, restore

    for i in range(90):
        repository.put(f"http:{i}", {"text": "synthetic"})
    with repository.store.connection() as db:
        assert db.execute("SELECT COUNT(*) FROM realtime_state").fetchone()[0] == 80
    repository.put("source:ames:nws_alerts", {"last_success_at": iso()})
    destination = tmp_path / "backup"
    backup(repository.store, destination)
    recovered = restore(destination, tmp_path / "restored")
    assert (
        Repository(recovered).get("source:ames:nws_alerts")["last_success_at"] == iso()
    )


@pytest.mark.asyncio
async def test_database_failure_is_not_a_success(repository):
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(fixture_response)
    ) as client:
        service = Realtime(repository.store, client=client)

        def broken(*args):
            raise OSError("disk unavailable")

        service.repository.put = broken
        with pytest.raises(OSError):
            await service.refresh("ames", "nws_alerts")
        assert (
            service.snapshot("ames")["sources"]["nws_alerts"]["status"] == "UNAVAILABLE"
        )


def test_private_api_cached_reads_origin_and_farm_ownership(repository):
    from fastapi.testclient import TestClient
    from earthsync.platform_v1.api import create_app, PREFIX
    from uuid import uuid4

    app = create_app(store=repository.store, local_enabled=True)
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 10000)
    ) as client:
        response = client.get(PREFIX + "/realtime/ames")
        assert (
            response.status_code == 200 and response.json()["worker_running"] is False
        )
        assert client.post(PREFIX + "/realtime/arbitrary/refresh").status_code == 404
        assert (
            client.get(
                PREFIX + "/realtime/ames", headers={"Origin": "https://evil.invalid"}
            ).status_code
            == 403
        )
        assert (
            client.get(
                PREFIX + "/realtime/ames", headers={"Host": "evil.invalid"}
            ).status_code
            == 403
        )
        assert client.get(PREFIX + f"/farms/{uuid4()}/realtime").status_code == 404
