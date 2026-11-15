import asyncio
import copy
import os
import time
from collections import OrderedDict
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Query, Request
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError

from .errors import ServiceError, error_response
from .models import SeasonQuery, SeasonResponse
from .power import PowerProvider, ProviderError
from .chat import router as chat_router
from .forecast import ForecastCache, OpenMeteoProvider
from .greenness import GreennessCache, StacSearch
from .greenness import router as greenness_router
from .forecast import router as forecast_router
from .recent import PowerRecentProvider, RecentCache
from .recent import router as recent_router
from .soil import router as soil_router


class SeasonCache:
    """Bounded per-process cache; a lock prevents duplicate concurrent fetches.

    A single lock deliberately serializes P0 misses to bound provider pressure.
    No disk retention, stale fallback, or cached failures.
    """

    def __init__(self, ttl=3600, capacity=128, clock=time.monotonic):
        self.ttl, self.capacity, self.clock = ttl, capacity, clock
        self.entries = OrderedDict()
        self.lock = asyncio.Lock()

    async def get(self, query, provider):
        key = tuple(query.model_dump().values())
        async with self.lock:
            now = self.clock()
            if key in self.entries:
                expires, value = self.entries[key]
                if expires > now:
                    self.entries.move_to_end(key)
                    result = copy.deepcopy(value)
                    result.cache = {"hit": True, "ttl_seconds": self.ttl}
                    return result
                del self.entries[key]
            value = await provider.season(query)
            value.cache = {"hit": False, "ttl_seconds": self.ttl}
            self.entries[key] = (self.clock() + self.ttl, copy.deepcopy(value))
            while len(self.entries) > self.capacity:
                self.entries.popitem(last=False)
            return value


def create_app(
    provider=None,
    cache=None,
    context_service=None,
    soil_estimator=None,
    recent_provider=None,
    recent_cache=None,
    forecast_provider=None,
    forecast_cache=None,
    greenness_search=None,
    greenness_reader=None,
    greenness_cache=None,
    chat_bot=None,
):
    diagnostics_enabled = os.getenv("EARTHSYNC_DIAGNOSTICS") == "1"
    @asynccontextmanager
    async def lifespan(app):
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(20, connect=5), follow_redirects=False
        ) as client:
            app.state.provider = provider or PowerProvider(client)
            app.state.cache = cache or SeasonCache()
            if context_service is not None:
                app.state.context_service = context_service
            else:
                from .environmental.service import ContextService
                from .environmental.soil import SoilGridsAdapter
                from .environmental.weather import WeatherAdapter

                app.state.context_service = ContextService(
                    SoilGridsAdapter(client), WeatherAdapter(client)
                )
            # Field Shift Today tasks (see recent.py); injectable for tests.
            app.state.recent_provider = recent_provider or PowerRecentProvider(client)
            app.state.recent_cache = recent_cache or RecentCache()
            app.state.forecast_provider = forecast_provider or OpenMeteoProvider(client)
            app.state.forecast_cache = forecast_cache or ForecastCache()
            app.state.greenness_search = greenness_search or StacSearch(client)
            app.state.greenness_cache = greenness_cache or GreennessCache()
            yield

    app = FastAPI(
        title="EarthSync NASA POWER backend", version="0.1.0", lifespan=lifespan
    )

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, exc):
        if request.url.path.startswith(
            (
                "/api/assistant/",
                "/api/environmental/",
                "/api/catalog/",
                "/api/satellite/",
            )
        ):
            return error_response(
                "INVALID_INPUT",
                "The versioned context request is invalid. Check the selected target, dates and evidence schema.",
                422,
            )
        return error_response(
            "INVALID_INPUT",
            "Provide valid coordinates and an ordered historical month window (maximum 24 months).",
            422,
        )

    @app.exception_handler(ServiceError)
    async def service_error(request, exc):
        return error_response(exc.code, exc.message, exc.status_code, exc.retryable)

    @app.exception_handler(ProviderError)
    async def upstream_error(request, exc):
        messages = {
            "UPSTREAM_NETWORK_UNAVAILABLE": "Cannot reach NASA POWER. Check the server's network and DNS connectivity.",
            "UPSTREAM_TIMEOUT": "NASA POWER exceeded the retrieval deadline. Retry later or request fewer months.",
            "UPSTREAM_UNAVAILABLE": "NASA POWER is temporarily unavailable or rate limited. Retry later.",
            "UPSTREAM_REJECTED": "NASA POWER rejected the request. Check the supported parameters and historical window.",
            "UPSTREAM_SOURCE_CHANGED": "NASA POWER returned unsupported source lineage. Only homogeneous MERRA-2 is accepted; no data were relabeled.",
            "UPSTREAM_UNITS_CHANGED": "NASA POWER parameter units differ from the validated contract.",
            "UPSTREAM_TIME_STANDARD_CHANGED": "NASA POWER did not return the requested LST time standard.",
            "UPSTREAM_INTERVAL_CHANGED": "NASA POWER returned a different historical interval.",
        }
        return error_response(
            exc.code,
            messages.get(
                exc.code, "NASA POWER returned an invalid response or metadata."
            ),
            504 if exc.code == "UPSTREAM_TIMEOUT" else (503 if exc.retryable else 502),
            exc.retryable,
        )

    async def diagnostic_nasa(request: Request):
        # No user coordinates or arbitrary upstream URL; always a public test point.
        if not diagnostics_enabled:
            raise ServiceError(
                "DIAGNOSTICS_DISABLED", "Developer diagnostics are disabled.", 404
            )
        if request.query_params or await request.body():
            raise ServiceError(
                "INVALID_INPUT", "This diagnostic accepts no inputs.", 422
            )
        result = await request.app.state.provider.season(
            SeasonQuery(
                latitude=16.85,
                longitude=96.15,
                start_year=2024,
                start_month=2,
                end_year=2024,
                end_month=2,
            )
        )
        if not all(
            row.rainfall_complete and row.temperature_complete
            for row in result.environment.seasonal.observations
        ):
            raise ServiceError(
                "MISSING_DATA",
                "NASA responded, but the diagnostic month has incomplete daily coverage.",
            )
        return result

    app.state.diagnostic_nasa = diagnostic_nasa

    @app.post("/api/v1/diagnostics/nasa")
    async def nasa_diagnostic(request: Request):
        await diagnostic_nasa(request)
        return {
            "schema_version": "1.0-diagnostic",
            "status": "success",
            "mode": "live_http",
            "cache_used": False,
            "checks": {
                "nasa_transport": "passed",
                "merra2_validation": "passed",
                "daily_coverage": "complete",
            },
        }
    # Field Shift photo soil check (see soil.py); injectable for tests.
    app.state.soil_estimator = soil_estimator
    app.include_router(soil_router)
    app.include_router(recent_router)
    app.include_router(forecast_router)
    # Farm greenness from NASA HLS; reader injectable for tests.
    app.state.greenness_reader = greenness_reader
    app.include_router(greenness_router)
    # Farm chat (Groq); bot injectable for tests.
    app.state.chat_bot = chat_bot
    app.include_router(chat_router)

    @app.get("/api/v1/health")
    async def health():
        return {
            "status": "ok",
            "service": "earthsync-climate",
            "upstream_checked": False,
        }

    @app.get("/api/v1/environment/season", response_model=SeasonResponse)
    async def season(
        request: Request,
        latitude: float = Query(ge=-90, le=90, allow_inf_nan=False),
        longitude: float = Query(ge=-180, le=180, allow_inf_nan=False),
        start_year: int = Query(ge=1981, le=9998),
        start_month: int = Query(ge=1, le=12),
        end_year: int = Query(ge=1981, le=9998),
        end_month: int = Query(ge=1, le=12),
    ):
        names = {
            "latitude",
            "longitude",
            "start_year",
            "start_month",
            "end_year",
            "end_month",
        }
        if set(request.query_params) != names or any(
            len(request.query_params.getlist(k)) != 1 for k in names
        ):
            raise RequestValidationError([])
        try:
            query = SeasonQuery(
                latitude=latitude,
                longitude=longitude,
                start_year=start_year,
                start_month=start_month,
                end_year=end_year,
                end_month=end_month,
            )
        except ValidationError as exc:
            raise RequestValidationError([]) from exc
        try:
            # Includes cache queueing: cannot wait indefinitely behind another miss.
            async with asyncio.timeout(80):
                return await request.app.state.cache.get(
                    query, request.app.state.provider
                )
        except TimeoutError:
            raise ServiceError(
                "BACKEND_TIMEOUT",
                "Climate request exceeded the server deadline; retry later.",
                504,
                True,
            ) from None

    return app


app = create_app()
