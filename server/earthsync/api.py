import asyncio
import copy
import time
from collections import OrderedDict
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import ValidationError

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
    @asynccontextmanager
    async def lifespan(app):
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(20, connect=5), follow_redirects=False
        ) as client:
            app.state.provider = provider or PowerProvider(client)
            app.state.cache = cache or SeasonCache()
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
        return JSONResponse(
            status_code=422,
            content={
                "status": "error",
                "error": {
                    "code": "INVALID_INPUT",
                    "message": "Provide valid coordinates and an ordered historical month window (maximum 24 months).",
                    "retryable": False,
                },
            },
        )

    @app.exception_handler(ProviderError)
    async def upstream_error(request, exc):
        return JSONResponse(
            status_code=503 if exc.retryable else 502,
            content={
                "status": "error",
                "error": {
                    "code": exc.code,
                    "message": "NASA POWER climate data could not be retrieved or validated.",
                    "retryable": exc.retryable,
                },
            },
        )

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
        return await request.app.state.cache.get(query, request.app.state.provider)

    return app


app = create_app()
