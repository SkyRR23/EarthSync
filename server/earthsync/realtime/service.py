"""One backend worker, private SQLite snapshots and cache-only browser reads."""

import asyncio
import json
import logging
import os
import time
from datetime import datetime, timezone

import httpx

from .http import CachedHttp, SourceError
from .nasa import NasaCatalog
from .nws_grid import NwsGrid
from .providers import (
    IowaStation,
    NwsAlerts,
    NwsForecast,
    OpenMeteo,
    local_time,
    timestamp,
)

LOG = logging.getLogger(__name__)
REFERENCES = [
    {
        "id": "ames",
        "name": "Ames, Iowa · public city reference",
        "lat": 42.0308,
        "lon": -93.6319,
        "country": "US",
        "timezone": "America/Chicago",
    },
    {
        "id": "crawfordsville",
        "name": "Crawfordsville, Iowa · public town reference",
        "lat": 41.2142,
        "lon": -91.5374,
        "country": "US",
        "timezone": "America/Chicago",
    },
    {
        "id": "davis",
        "name": "Davis, California · public city reference",
        "lat": 38.5449,
        "lon": -121.7405,
        "country": "US",
        "timezone": "America/Los_Angeles",
    },
    {
        "id": "yangon",
        "name": "Yangon, Myanmar · public city reference",
        "lat": 16.8661,
        "lon": 96.1951,
        "country": "MM",
        "timezone": "Asia/Yangon",
    },
    {
        "id": "mandalay",
        "name": "Mandalay, Myanmar · public city reference",
        "lat": 21.9588,
        "lon": 96.0891,
        "country": "MM",
        "timezone": "Asia/Yangon",
    },
]


class Repository:
    """Same private database and backup boundary as the existing platform."""

    def __init__(self, store):
        self.store = store

    def get(self, key):
        with self.store.connection() as db:
            row = db.execute(
                "SELECT payload FROM realtime_state WHERE key=?", (key,)
            ).fetchone()
        return json.loads(row[0]) if row else None

    def put(self, key, value):
        payload = json.dumps(value, allow_nan=False, separators=(",", ":"))
        if len(payload.encode()) > 4_000_000:
            raise SourceError("STORAGE_QUOTA")
        with self.store.connection() as db:
            db.execute(
                "INSERT INTO realtime_state VALUES (?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload",
                (key, payload),
            )
            # Fixed latest-source slots plus a bounded LRU-like HTTP working set.
            db.execute(
                "DELETE FROM realtime_state WHERE key IN (SELECT key FROM realtime_state WHERE key LIKE 'http:%' ORDER BY rowid DESC LIMIT -1 OFFSET 80)"
            )
            db.execute(
                "DELETE FROM realtime_state WHERE key IN (SELECT key FROM realtime_state WHERE key LIKE 'source:farm:%' ORDER BY rowid DESC LIMIT -1 OFFSET 40)"
            )
            db.execute(
                "DELETE FROM realtime_state WHERE key IN (SELECT key FROM realtime_state WHERE key LIKE 'qa:%' ORDER BY rowid DESC LIMIT -1 OFFSET 64)"
            )


class Realtime:
    def __init__(self, store, *, client=None, clock=time.time, enabled=True, gfs=None):
        self.repository, self.clock, self.enabled = Repository(store), clock, enabled
        if os.getenv("EARTHSYNC_PUBLIC_NASA_CACHE") == "1":
            from .public_cache import seed

            seed(self.repository)
        self.client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(20),
            limits=httpx.Limits(max_connections=4, max_keepalive_connections=4),
        )
        self.owns_client = client is None
        self.http = CachedHttp(self.client, self.repository, clock)
        self.adapters = {
            "iowa_station": IowaStation(self.http),
            "nws_forecast": NwsForecast(self.http),
            "nws_grid": NwsGrid(self.http),
            "nws_alerts": NwsAlerts(self.http),
            "open_meteo": OpenMeteo(self.http),
            "nasa_catalog": NasaCatalog(self.http),
        }
        if gfs is not None:
            from .gfs import GfsWeather

            self.adapters["noaa_gfs"] = GfsWeather(gfs)
        from .nasa_numeric import NasaNumeric

        nasa_slots = asyncio.Lock()
        for product in ("imerg", "smap", "hls_ndvi"):
            self.adapters[product] = NasaNumeric(self.http, product, nasa_slots)
        self.locations = {r["id"]: r for r in REFERENCES}
        # Only Ames is monitored without user selection; secondary sites opt in.
        self.active = {"ames"}
        self.lock = asyncio.Lock()
        self.task = None
        self.inflight = {}
        self.auth_retried = set()
        self.wake = asyncio.Event()
        self.running = False

    async def start(self):
        if self.enabled:
            self.running = True
            self.task = asyncio.create_task(self._run(), name="earthsync-realtime")

    async def close(self):
        self.running = False
        for adapter in self.adapters.values():
            if hasattr(adapter, "stop"):
                adapter.stop()
        if self.task:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
        pending = list(self.inflight.values())
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        if self.owns_client:
            await self.client.aclose()

    async def _run(self):
        while True:
            self.wake.clear()
            for location in list(self.active):
                for source in self.adapters:
                    key = (location, source)
                    if key not in self.inflight or self.inflight[key].done():
                        self.inflight[key] = asyncio.create_task(
                            self._refresh_safely(location, source)
                        )
            try:
                await asyncio.wait_for(self.wake.wait(), timeout=5)
            except TimeoutError:
                pass

    async def _refresh_safely(self, location, source):
        try:
            await self.refresh(location, source)
        except Exception:
            # Never log raw private coordinates, auth material or provider bodies.
            LOG.error("Realtime source refresh failed; persisted snapshot retained")

    def activate(self, location_id):
        if location_id not in self.locations:
            raise KeyError(location_id)
        self.active.add(location_id)
        self.wake.set()

    def farm_location(self, farm):
        point = farm.confirmed_point
        location_id = "farm:" + str(farm.id)
        if location_id not in self.locations:
            # At most four explicitly selected farm revisions per backend run.
            farm_keys = [key for key in self.locations if key.startswith("farm:")]
            if len(farm_keys) >= 4:
                removed = farm_keys[0]
                self.active.discard(removed)
                for key in [k for k in self.inflight if k[0] == removed]:
                    self.inflight.pop(key).cancel()
                del self.locations[removed]
                with self.repository.store.connection() as db:
                    db.execute(
                        "DELETE FROM realtime_state WHERE key LIKE ?",
                        ("source:" + removed + ":%",),
                    )
            us_candidate = 24 <= point.latitude <= 50 and -125 <= point.longitude <= -66
            self.locations[location_id] = {
                "id": location_id,
                "name": "Selected confirmed field · nearby/regional context",
                "lat": point.latitude,
                "lon": point.longitude,
                "country": "US" if us_candidate else "OTHER",
                "timezone": "UTC",
            }
        self.activate(location_id)
        return location_id

    async def tick(self):
        async with self.lock:
            # Provider host locks serialize outbound traffic; location fanout stays bounded.
            await asyncio.gather(
                *(
                    self.refresh(location, source)
                    for location in list(self.active)
                    for source in self.adapters
                )
            )

    async def refresh(self, location_id, source):
        adapter = self.adapters[source]
        key = f"source:{location_id}:{source}"
        state = self.repository.get(key) or {
            "data": None,
            "failures": 0,
            "last_success_at": None,
        }
        epoch = self.clock()
        retry_auth = (
            source in {"imerg", "smap", "hls_ndvi"}
            and bool(os.getenv("EARTHDATA_TOKEN"))
            and state.get("error")
            in {"AUTHENTICATION_REQUIRED", "AUTHORIZATION_DENIED"}
            and key not in self.auth_retried
        )
        if state.get("next_check", 0) > epoch and not retry_auth:
            return
        if retry_auth:
            # Newly configured credentials get one attempt per source/run.
            # Rejected credentials still retain the ordinary provider backoff.
            self.auth_retried.add(key)
        now = datetime.fromtimestamp(epoch, timezone.utc)
        location = self.locations[location_id]
        if (source.startswith("nws_") and location["country"] != "US") or (
            source == "iowa_station"
            and not (
                40.3 <= location["lat"] <= 43.6 and -96.7 <= location["lon"] <= -90.1
            )
        ):
            state.update(
                error="GEOGRAPHIC_NON_COVERAGE",
                last_attempt_at=now.isoformat(),
                next_check=epoch + 86400,
            )
            self.repository.put(key, state)
            return
        started = time.perf_counter()
        try:
            data = await adapter.fetch(location, state["data"], now)
            checked = data.get("checked_at") or max(
                r["retrieved_at"] for r in data["provenance"]
            )
            state.update(
                data=data,
                error=None,
                failures=0,
                last_success_at=checked,
                next_check=max(epoch + adapter.interval, data.get("next_check", 0)),
            )
        except (SourceError, KeyError, ValueError, TypeError, OverflowError) as exc:
            code = exc.code if isinstance(exc, SourceError) else "INVALID_DATA"
            failures = min(8, state["failures"] + 1)
            backoff = max(
                60
                if code
                in {
                    "PROVIDER_OUTAGE",
                    "PROVIDER_TIMEOUT",
                    "NETWORK_OR_TLS_ERROR",
                    "NETWORK_POLICY_OR_PROXY",
                    "RATE_LIMIT",
                    "PROVIDER_BACKOFF",
                    "TIMEOUT",
                    "PROVIDER_UNAVAILABLE",
                }
                else adapter.interval,
                min(3600, 60 * 2 ** (failures - 1)),
                getattr(exc, "retry_after", 0),
            )
            state.update(
                error=code,
                failures=failures,
                next_check=epoch
                + (86400 if code == "GEOGRAPHIC_NON_COVERAGE" else backoff),
            )
        state.update(
            last_attempt_at=now.isoformat(),
            processing_ms=round((time.perf_counter() - started) * 1000, 2),
        )
        self.repository.put(key, state)

    def snapshot(self, location_id):
        location = self.locations[location_id]
        now = self.clock()
        output = {}
        for source, adapter in self.adapters.items():
            state = self.repository.get(f"source:{location_id}:{source}") or {}
            data = state.get("data")
            age = (
                now - timestamp(state["last_success_at"]).timestamp()
                if state.get("last_success_at")
                else None
            )
            unsupported = (
                source.startswith("nws_") and location["country"] != "US"
            ) or (
                source == "iowa_station"
                and not (
                    40.3 <= location["lat"] <= 43.6
                    and -96.7 <= location["lon"] <= -90.1
                )
            )
            status = "UNAVAILABLE" if not data else "FRESH"
            if unsupported:
                status = "GEOGRAPHIC_NON_COVERAGE"
            if data:
                if (
                    state.get("error")
                    or age is None
                    or age > adapter.stale_after
                    or not self.running
                ):
                    status = "CACHED_REAL_STALE"
                if (
                    source == "iowa_station"
                    and now - timestamp(data["observed_at"]).timestamp()
                    > adapter.stale_after
                ):
                    status = "CACHED_REAL_STALE"
                if (
                    data.get("valid_until")
                    and timestamp(data["valid_until"]).timestamp() <= now
                ):
                    status = "EXPIRED"
                # Never serve expired alerts as active after a successful old snapshot.
                if source == "nws_alerts":
                    data["alerts"] = [
                        a
                        for a in data["alerts"]
                        if timestamp(a.get("ends") or a["expires"]).timestamp() > now
                        and timestamp(a["expires"]).timestamp() > now
                    ]
                if source == "iowa_station":
                    for m in data["measurements"]:
                        m["status"] = (
                            "FRESH"
                            if status == "FRESH"
                            and now - timestamp(m["observed_at"]).timestamp()
                            <= adapter.stale_after
                            else "CACHED_REAL_STALE"
                        )
                        m["observed_local"] = local_time(
                            m["observed_at"], location["timezone"]
                        )
            message = None
            if source == "nws_alerts":
                message = "Official alert status could not be verified."
                if status == "FRESH":
                    message = (
                        "Active official alerts found."
                        if data["alerts"]
                        else "No active official alerts found at the last successful check."
                    )
            # Rolling records are private persistence; the browser needs only latest sensors.
            visible_data = (
                {
                    k: v
                    for k, v in data.items()
                    if source != "iowa_station" or k != "records"
                }
                if data
                else None
            )
            output[source] = {
                "source": source,
                "data_type": adapter.kind,
                "status": (
                    "METADATA_ONLY"
                    if adapter.kind == "METADATA_ONLY"
                    else "LATEST_AVAILABLE_DELAYED"
                    if adapter.kind.startswith("LATEST_")
                    else status
                )
                if status == "FRESH"
                else status,
                "data": visible_data,
                "error": "GEOGRAPHIC_NON_COVERAGE"
                if unsupported
                else state.get("error"),
                "last_attempt_at": state.get("last_attempt_at"),
                "last_success_at": state.get("last_success_at"),
                "cache_age_seconds": round(age, 1) if age is not None else None,
                "next_check_at": datetime.fromtimestamp(
                    state["next_check"], timezone.utc
                ).isoformat()
                if state.get("next_check")
                else None,
                "processing_ms": state.get("processing_ms"),
                "message": message,
                "limitations": adapter.limitations,
                "poll_interval_seconds": adapter.interval,
                "latency": {
                    "observation_to_publication_seconds": None,
                    "publication_to_ingestion_seconds": None,
                    "observation_to_ingestion_seconds": (
                        timestamp(data.get("ingested_at") or state["last_success_at"])
                        - timestamp(data["observed_at"])
                    ).total_seconds()
                    if data and data.get("observed_at") and state.get("last_success_at")
                    else None,
                },
            }
        return {
            "contract": "earthsync.realtime.v1",
            "location": location,
            "generated_at": datetime.fromtimestamp(now, timezone.utc).isoformat(),
            "worker_running": self.running,
            "sources": output,
            "scientific_status": "60 blocked rule candidates; zero approved executable crop-suitability recommendations. Latest context does not rank strategies.",
            "satellite_status": {
                name: output[name]["status"]
                + (" · " + output[name]["error"] if output[name]["error"] else "")
                for name in ("imerg", "smap", "hls_ndvi")
            },
        }
