"""Standalone local-only 7I application. No 7H router or launcher edits."""

import asyncio
import ipaddress
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID

import httpx
from fastapi import FastAPI, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import AwareDatetime, Field
from starlette.concurrency import run_in_threadpool

from datetime import date

from .historical_imagery import imagery
from .historical import ArchiveInput, Historical, SimulationInput
from .journal import Journal, JournalInput
from .farmer_timeline import timeline
from .comparisons import Comparisons, ComparisonInput
from .availability import SourceHealth
from .catalog import Catalog
from .context import assistant_context
from .engine import RustEngine
from .errors import PlatformError
from .jobs import Jobs
from .models import (
    AssessmentInput,
    ClimateQuery,
    Contract,
    Evidence,
    Farm,
    FarmInput,
    FarmLinkInput,
    Point,
    HistoryInput,
    ObservationInput,
)
from .objects import LocalObjects
from .orchestrate import Orchestrator
from .providers.discovery import DiscoveryQuery, HlsDiscovery
from .providers.power_daily import POLICY, PowerDaily
from .providers.soil_wcs import SoilQuery, SoilWcs
from .providers.soil_webdav import SoilWebdav
from .providers.gfs import GfsForecast
from .providers.transport import Transport
from .store import Store, cache_key
from .reference_v2 import ReferenceCatalog, ROOT as REFERENCE_ROOT
from .water import WaterPipeline, POLICY as WATER_POLICY

PREFIX = "/api/platform/v1"
OWNER = "local-single-user"


class ClimateInput(Contract):
    query: ClimateQuery
    farm_id: UUID | None = None


class SoilInput(Contract):
    point: Point
    farm_id: UUID | None = None


class OpticalInput(Contract):
    farm_id: UUID
    start: AwareDatetime
    end: AwareDatetime
    product: str = Field(default="HLSS30", pattern="^(HLSL30|HLSS30)$")


def create_app(
    *,
    store=None,
    engine=None,
    catalog=None,
    reference_catalog=None,
    transport=None,
    objects=None,
    local_enabled=False,
    allowed_origins=(),
    rate_limit=120,
):
    # This is intentionally not a custom authentication protocol. No hosted
    # private API is enabled until an identity provider integration is reviewed.
    if not local_enabled:
        raise ValueError(
            "Private platform disabled: explicitly enable local single-user mode"
        )
    for origin in allowed_origins:
        from urllib.parse import urlsplit

        parsed = urlsplit(origin)
        if (
            parsed.scheme not in ("http", "https")
            or parsed.hostname not in ("localhost", "127.0.0.1", "::1")
            or parsed.path not in ("", "/")
        ):
            raise ValueError("Local demo origins must be exact loopback origins")
    store = store or Store(Path(os.environ["EARTHSYNC_PLATFORM_DIR"]))
    engine = engine or RustEngine(
        os.getenv("EARTHSYNC_V03_EXECUTABLE"), os.getenv("EARTHSYNC_V03_SHA256")
    )
    catalog = catalog or Catalog(
        os.getenv("EARTHSYNC_CATALOG_PATH"), os.getenv("EARTHSYNC_CATALOG_SHA256")
    )
    client = (
        httpx.AsyncClient(
            timeout=25,
            limits=httpx.Limits(max_connections=4, max_keepalive_connections=2),
        )
        if transport is None
        else None
    )
    transport = transport or Transport(client)
    power, soil, optical = (
        PowerDaily(transport),
        SoilWcs(transport),
        HlsDiscovery(transport),
    )
    soil_map = SoilWebdav(transport, store)
    forecast_source = GfsForecast(transport, store)
    health = SourceHealth()
    objects = objects or LocalObjects(store)
    reference_catalog = reference_catalog or (
        ReferenceCatalog() if REFERENCE_ROOT.is_dir() else None
    )
    orchestrator = Orchestrator(store, engine, catalog, reference_catalog)
    water = WaterPipeline(transport, engine)
    historical = Historical(store, transport, engine, orchestrator)

    def association(farm_id, point):
        if farm_id and store.farm(OWNER, farm_id).confirmed_point != point:
            raise PlatformError("SPATIAL_MISMATCH")

    async def climate_handler(owner, raw):
        value = ClimateInput.model_validate(raw)
        association(value.farm_id, value.query.point)
        key = cache_key(
            "NASA POWER", "daily", POLICY, value.query.model_dump(mode="json")
        )
        result = store.cache_get(key)
        hit = result is not None
        if result is None:
            result = await power.retrieve(value.query)
            # Do not cache provider failures as successful empty responses.
            if result["records"] and not result["gaps"]:
                store.cache_put(key, result)
        for item in result["records"]:
            store.save_evidence(owner, Evidence.model_validate(item), value.farm_id)
        for gap in result["gaps"]:
            health.record(
                "NASA POWER:" + gap["parameter"], gap["code"], gap["retryable"]
            )
        if not result["gaps"]:
            health.record("NASA POWER", "OK")
        return {**result, "cache_hit": hit}

    async def water_handler(owner, raw):
        value = ClimateInput.model_validate(raw)
        association(value.farm_id, value.query.point)
        key = cache_key(
            "NASA POWER",
            "water-inputs",
            WATER_POLICY,
            value.query.model_dump(mode="json"),
        )
        result = store.cache_get(key)
        hit = result is not None
        if result is None:
            result = await water.retrieve(value.query)
            if result["records"] and not result["gaps"]:
                store.cache_put(key, result)
        calculated = await water.calculate(result["records"], value.query)
        records = [*result["records"], calculated.model_dump(mode="json")]
        for item in records:
            store.save_evidence(owner, Evidence.model_validate(item), value.farm_id)
        for gap in result["gaps"]:
            health.record(
                "NASA POWER:" + gap["parameter"], gap["code"], gap["retryable"]
            )
        return {**result, "records": records, "cache_hit": hit}

    async def soil_handler(owner, raw):
        value = SoilInput.model_validate(raw)
        association(value.farm_id, value.point)
        try:
            result = await soil.retrieve(SoilQuery(point=value.point))
            health.record("ISRIC WCS", "OK")
            store.save_evidence(owner, result, value.farm_id)
            return result.model_dump(mode="json")
        except PlatformError as exc:
            health.record("ISRIC WCS", exc.code, exc.retryable)
            raise

    async def optical_handler(owner, raw):
        value = OpticalInput.model_validate(raw)
        farm = store.farm(owner, value.farm_id)
        try:
            result = await optical.retrieve(
                DiscoveryQuery(
                    farm=farm.model_dump(exclude={"id"}),
                    start=value.start,
                    end=value.end,
                    product=value.product,
                )
            )
            health.record("NASA HLS CMR", "OK")
            return result
        except PlatformError as exc:
            health.record("NASA HLS CMR", exc.code, exc.retryable)
            raise

    async def soil_map_handler(owner, raw):
        value = SoilInput.model_validate(raw)
        association(value.farm_id, value.point)
        return await soil_map.retrieve(value.point)

    async def forecast_handler(owner, raw):
        value = SoilInput.model_validate(raw)
        association(value.farm_id, value.point)
        return await forecast_source.retrieve(value.point)

    jobs = Jobs(
        store,
        {
            "historical": historical.retrieve,
            "simulation": historical.simulate,
            "climate": climate_handler,
            "water": water_handler,
            "soil": soil_handler,
            "soil_map": soil_map_handler,
            "forecast": forecast_handler,
            "optical_discovery": optical_handler,
        },
    )

    engine_checked = False

    @asynccontextmanager
    async def lifespan(app):
        nonlocal engine_checked
        if engine.ready:
            try:
                await engine.probe()
                engine_checked = True
            except PlatformError as exc:
                health.record("Rust v0.3", exc.code, exc.retryable)
        await jobs.start()
        yield
        await jobs.close()
        if client:
            await client.aclose()

    app = FastAPI(
        title="EarthSync backend evidence platform (local single-user)",
        version="1.0.0",
        lifespan=lifespan,
    )
    app.state.jobs, app.state.store = jobs, store
    if allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(allowed_origins),
            allow_methods=["GET", "POST", "DELETE"],
            allow_headers=["Content-Type"],
        )
    admission = asyncio.Semaphore(8)
    image_slots = asyncio.Semaphore(2)
    # One local principal, one bounded counter; no dictionary keyed by user input.
    window_start, attempts = time.monotonic(), 0

    @app.middleware("http")
    async def local_boundary(request, call_next):
        nonlocal window_start, attempts

        def reject(code, status):
            return JSONResponse(
                {"error": {"code": code, "retryable": status == 429}},
                status_code=status,
            )

        try:
            peer_ok = (
                request.client and ipaddress.ip_address(request.client.host).is_loopback
            )
        except ValueError:
            peer_ok = False
        if not peer_ok or request.url.hostname not in (
            "localhost",
            "127.0.0.1",
            "::1",
            "testserver",
        ):
            return reject("LOCAL_ONLY", 403)
        origin = request.headers.get("origin")
        if origin and origin not in allowed_origins:
            return reject("ORIGIN_FORBIDDEN", 403)
        if time.monotonic() - window_start >= 60:
            window_start, attempts = time.monotonic(), 0
        attempts += 1
        if attempts > rate_limit:
            return reject("RATE_LIMIT", 429)
        # Cap the raw ASGI stream before FastAPI's JSON parsing or upload buffer.
        limit = (
            10 * 1024 * 1024
            if request.url.path.endswith("/photos") and request.method == "POST"
            else 2_000_000
        )
        received = 0
        receive = request._receive

        async def bounded_receive():
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    raise PlatformError("REQUEST_TOO_LARGE", 413)
            return message

        declared = request.headers.get("content-length")
        if declared is not None:
            try:
                if int(declared) < 0:
                    return reject("INVALID_INPUT", 422)
                if int(declared) > limit:
                    return reject("REQUEST_TOO_LARGE", 413)
            except ValueError:
                return reject("INVALID_INPUT", 422)
        request._receive = bounded_receive
        try:
            async with asyncio.timeout(45):
                async with admission:
                    response = await call_next(request)
        except PlatformError as exc:
            response = reject(exc.code, exc.status)
        except TimeoutError:
            response = reject("TIMEOUT", 504)
        if received > limit:
            response = reject("REQUEST_TOO_LARGE", 413)
        response.headers.update(
            {
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
                "Referrer-Policy": "no-referrer",
            }
        )
        return response

    @app.exception_handler(PlatformError)
    async def platform_error(request, exc):
        return JSONResponse(
            {
                "error": {
                    "code": exc.code,
                    "retryable": exc.retryable,
                    **({"validation": exc.validation} if exc.validation else {}),
                }
            },
            status_code=exc.status,
        )

    @app.exception_handler(RequestValidationError)
    async def invalid(request, exc):
        return JSONResponse(
            {"error": {"code": "INVALID_INPUT", "retryable": False}}, status_code=422
        )

    @app.exception_handler(Exception)
    async def internal(request, exc):
        return JSONResponse(
            {"error": {"code": "INTERNAL_ERROR", "retryable": False}}, status_code=500
        )

    @app.get(PREFIX + "/health")
    def liveness():
        return {
            "status": "ok",
            "mode": "local_single_user",
            "schema_version": "earthsync.evidence.v1.0",
        }

    @app.get(PREFIX + "/ready")
    def readiness(response: Response):
        storage = store.ready()
        ready = storage and engine_checked
        response.status_code = 200 if ready else 503
        return {
            "ready": ready,
            "storage": storage,
            "rust_v03_configured": engine.ready,
            "rust_v03_startup_probe_passed": engine_checked,
            "catalog_installed": catalog.data is not None,
            "crop_reference_v2_installed": reference_catalog is not None,
            "hosted_private_api_enabled": False,
            "limitation": "Storage integrity and actual Rust startup execution; external provider availability is separate.",
        }

    @app.get(PREFIX + "/providers")
    def providers():
        return health.snapshot()

    @app.post(PREFIX + "/farms", response_model=Farm, status_code=201)
    def create_farm(value: FarmInput):
        return store.create_farm(OWNER, value)

    @app.get(PREFIX + "/farms", response_model=list[Farm])
    def farms():
        return store.farms(OWNER)

    @app.post(PREFIX + "/farm-links", status_code=201)
    def link_farm(value: FarmLinkInput):
        return store.link_farm(OWNER, value)

    @app.get(PREFIX + "/farm-links/{local_profile_id}")
    def farm_link(local_profile_id: str, revision: AwareDatetime):
        return store.farm_link(OWNER, local_profile_id, revision)

    @app.get(PREFIX + "/farms/{farm_id}", response_model=Farm)
    def farm(farm_id: UUID):
        return store.farm(OWNER, farm_id)

    @app.get(PREFIX + "/farms/{farm_id}/context")
    def context(farm_id: UUID):
        farm = store.farm(OWNER, farm_id)
        return {
            "farm": farm,
            "evidence": store.farm_records(OWNER, farm_id),
            "history": store.history(OWNER, farm_id),
            "production_system": farm.production_system,
            "agricultural_diagnosis": None,
        }

    @app.get(PREFIX + "/farms/{farm_id}/observations")
    def observations(farm_id: UUID):
        return store.observations(OWNER, farm_id)

    @app.post(PREFIX + "/farms/{farm_id}/observations", status_code=201)
    def report_observation(farm_id: UUID, value: ObservationInput):
        return store.save_observation(OWNER, farm_id, value)

    @app.get(PREFIX + "/farms/{farm_id}/assistant-context")
    def assistant(farm_id: UUID):
        return assistant_context(store, OWNER, farm_id)

    @app.post(PREFIX + "/farms/{farm_id}/history", status_code=201)
    def report_history(farm_id: UUID, value: HistoryInput):
        return store.save_history(OWNER, farm_id, value)

    @app.get(PREFIX + "/farms/{farm_id}/history")
    def history(farm_id: UUID):
        return store.history(OWNER, farm_id)

    @app.get(PREFIX + "/farms/{farm_id}/timeline")
    def farmer_timeline(farm_id: UUID):
        return timeline(store, OWNER, farm_id)

    @app.get(PREFIX + "/farms/{farm_id}/comparisons")
    def comparisons(farm_id: UUID):
        return Comparisons(store).list(OWNER, farm_id)

    @app.post(PREFIX + "/farms/{farm_id}/comparisons", status_code=201)
    def save_comparison(farm_id: UUID, value: ComparisonInput):
        return Comparisons(store).save(OWNER, farm_id, value)

    @app.get(PREFIX + "/farms/{farm_id}/journal")
    def journal(farm_id: UUID):
        return Journal(store).list(OWNER, farm_id)

    @app.post(PREFIX + "/farms/{farm_id}/journal", status_code=201)
    def report_journal(farm_id: UUID, value: JournalInput):
        return Journal(store).save(OWNER, farm_id, value)

    @app.post(
        PREFIX + "/farms/{farm_id}/journal/{entry_id}/confirm-history", status_code=201
    )
    def confirm_journal_history(farm_id: UUID, entry_id: UUID):
        return Journal(store).confirm_history(OWNER, farm_id, entry_id)

    @app.get(PREFIX + "/historical/imagery")
    async def historical_imagery(day: date):
        if day >= date.today():
            raise PlatformError("HISTORICAL_DATE_REQUIRED", 422)
        return await imagery(store, transport, day)

    @app.post(PREFIX + "/historical/jobs", status_code=202)
    async def historical_job(value: ArchiveInput):
        historical.revision(OWNER, value.farm_id, value.revision)
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER, "historical", cache_key("POWER", "historical", "v1", raw), raw
        )

    @app.get(PREFIX + "/farms/{farm_id}/historical")
    def historical_windows(farm_id: UUID):
        return historical.list(OWNER, farm_id, "historical_windows")

    @app.get(PREFIX + "/farms/{farm_id}/historical/{archive_id}")
    def historical_replay(farm_id: UUID, archive_id: UUID):
        return historical.replay(OWNER, farm_id, archive_id)

    @app.post(PREFIX + "/simulations/jobs", status_code=202)
    async def simulation_job(value: SimulationInput):
        historical.revision(OWNER, value.farm_id, value.revision)
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER,
            "simulation",
            cache_key("Rust", "historical-simulation", "v1", raw),
            raw,
        )

    @app.get(PREFIX + "/farms/{farm_id}/simulations")
    def simulations(farm_id: UUID):
        return historical.list(OWNER, farm_id, "historical_simulations")

    @app.get(PREFIX + "/farms/{farm_id}/simulations/{simulation_id}")
    def simulation(farm_id: UUID, simulation_id: UUID):
        return historical.get(OWNER, farm_id, simulation_id, "historical_simulations")

    @app.post(PREFIX + "/climate/jobs", status_code=202)
    async def climate(value: ClimateInput):
        association(value.farm_id, value.query.point)
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER, "climate", cache_key("POWER", "job", POLICY, raw), raw
        )

    @app.post(PREFIX + "/soil/jobs", status_code=202)
    async def soil_job(value: SoilInput):
        association(value.farm_id, value.point)
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER, "soil", cache_key("ISRIC", "WCS-pH", "probe.v1", raw), raw
        )

    @app.post(PREFIX + "/soil-map/jobs", status_code=202)
    async def soil_map_job(value: SoilInput):
        if value.farm_id is None:
            raise PlatformError("FARM_REQUIRED", 422)
        association(value.farm_id, value.point)
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER, "soil_map", cache_key("ISRIC", "WebDAV-pH", "v1", raw), raw
        )

    @app.post(PREFIX + "/forecast/jobs", status_code=202)
    async def forecast_job(value: SoilInput):
        if value.farm_id is None:
            raise PlatformError("FARM_REQUIRED", 422)
        association(value.farm_id, value.point)
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER, "forecast", cache_key("NOAA", "GFS", "v1", raw), raw
        )

    @app.get(PREFIX + "/farms/{farm_id}/intelligence")
    def intelligence(farm_id: UUID):
        store.farm(OWNER, farm_id)
        return store.intelligence(OWNER, farm_id)

    @app.post(PREFIX + "/water/jobs", status_code=202)
    async def water_job(value: ClimateInput):
        association(value.farm_id, value.query.point)
        if value.query.start.year < 2001:
            raise PlatformError("UNSUPPORTED_WATER_PRODUCT_PERIOD", 422)
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER, "water", cache_key("POWER", "water-job", WATER_POLICY, raw), raw
        )

    @app.get(PREFIX + "/crop-references")
    def references(
        q: str = Query(default="rice", min_length=1, max_length=150),
        region: str | None = Query(default=None, max_length=150),
        system: str | None = Query(default=None, max_length=150),
        cultivar: str | None = Query(default=None, max_length=150),
    ):
        if reference_catalog is None:
            raise PlatformError("CATALOG_NOT_INSTALLED", 503)
        return reference_catalog.lookup(q, region, system, cultivar)

    def identity_matches(q):
        if reference_catalog is None:
            raise PlatformError("CATALOG_NOT_INSTALLED", 503)
        query = q.strip().casefold()
        return [
            c
            for c in reference_catalog.data["crops"]
            if not query
            or any(query in n.casefold() for n in [c["scientific_name"], *c["aliases"]])
        ]

    @app.get(PREFIX + "/crop-options")
    def crop_options(q: str = Query(default="", max_length=150)):
        crops = identity_matches(q)
        return {
            "schema_version": "earthsync.crop-options.v1",
            "catalog_sha256": reference_catalog.sha256,
            "crops": crops[:100],
            "total_matches": len(crops),
            "recommendation_eligible": False,
        }

    @app.get(PREFIX + "/crop-identities")
    def crop_identities(q: str = Query(default="", max_length=150)):
        crops = identity_matches(q)
        return {
            "records": [
                {
                    "id": c["id"],
                    "scientific_name": c["scientific_name"],
                    "aliases": c["aliases"],
                    "review": "reference_only",
                }
                for c in crops[:50]
            ],
            "truncated": len(crops) > 50,
            "recommendation_eligible": False,
            "catalog_sha256": reference_catalog.sha256,
        }

    @app.post(PREFIX + "/optical/jobs", status_code=202)
    async def optical_job(value: OpticalInput):
        store.farm(OWNER, value.farm_id)
        if not 0 <= (value.end - value.start).total_seconds() <= 366 * 86400:
            raise PlatformError("INVALID_INPUT")
        raw = value.model_dump(mode="json")
        return await jobs.submit(
            OWNER,
            "optical_discovery",
            cache_key("HLS", value.product, "2.0-discovery.v1", raw),
            raw,
        )

    @app.get(PREFIX + "/jobs/{job_id}")
    def job(job_id: UUID):
        return jobs.get(OWNER, job_id)

    @app.delete(PREFIX + "/jobs/{job_id}")
    def cancel(job_id: UUID):
        return jobs.cancel(OWNER, job_id)

    @app.get(PREFIX + "/evidence/{evidence_id}", response_model=Evidence)
    def evidence(evidence_id: str):
        return store.evidence(OWNER, evidence_id)

    @app.get(PREFIX + "/catalog/{profile_id}")
    def crop(profile_id: str):
        return {
            "profile": catalog.lookup(profile_id),
            "recommendation_eligible": False,
            "catalog_sha256": catalog.sha256,
        }

    @app.post(PREFIX + "/assessments")
    async def assess(value: AssessmentInput):
        return await orchestrator.assess(OWNER, value)

    @app.get(PREFIX + "/farms/{farm_id}/decisions/{decision_id}")
    def decision(farm_id: UUID, decision_id: UUID):
        return store.decision(OWNER, farm_id, decision_id)

    @app.get(PREFIX + "/farms/{farm_id}/decisions")
    def decisions(farm_id: UUID):
        return store.decisions(OWNER, farm_id)

    @app.post(PREFIX + "/farms/{farm_id}/photos", status_code=201)
    async def upload(farm_id: UUID, request: Request):
        store.farm(OWNER, farm_id)
        # Entire upload+decode is under bounded request admission; sanitizer's
        # existing limits and metadata stripping are reused without duplication.
        async with image_slots:
            raw = await request.body()
            clean = await run_in_threadpool(
                objects.clean, raw, request.headers.get("content-type", "")
            )
            return await run_in_threadpool(objects.save_photo, OWNER, farm_id, clean)

    @app.get(PREFIX + "/farms/{farm_id}/photos")
    def photos(farm_id: UUID):
        return objects.list(OWNER, farm_id)

    @app.get(PREFIX + "/farms/{farm_id}/photos/{photo_id}/image")
    def photo_image(farm_id: UUID, photo_id: UUID):
        return Response(
            objects.image(OWNER, farm_id, photo_id),
            media_type="image/png",
            headers={
                "Content-Security-Policy": "default-src 'none'; sandbox",
                "Content-Disposition": 'inline; filename="farm-photo.png"',
            },
        )

    @app.delete(PREFIX + "/farms/{farm_id}/photos/{photo_id}", status_code=204)
    def delete_photo(farm_id: UUID, photo_id: UUID):
        objects.delete(OWNER, farm_id, photo_id)
        return Response(status_code=204)

    return app


def app_factory():
    return create_app(
        local_enabled=os.getenv("EARTHSYNC_PLATFORM_LOCAL") == "1",
        allowed_origins=tuple(
            filter(None, os.getenv("EARTHSYNC_PLATFORM_ORIGINS", "").split(","))
        ),
    )
