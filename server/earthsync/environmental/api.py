"""Standalone additive API. Does not mount or change the NASA POWER routes."""

from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .models import ContextQuery, ContextResponse
from .service import ContextService
from .soil import SoilGridsAdapter
from .weather import WeatherAdapter


def create_app(service=None):
    @asynccontextmanager
    async def lifespan(app):
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(20, connect=5), follow_redirects=False
        ) as client:
            app.state.service = service or ContextService(
                SoilGridsAdapter(client), WeatherAdapter(client)
            )
            yield

    app = FastAPI(
        title="EarthSync optional environmental context",
        version="1.0-proposal",
        lifespan=lifespan,
    )

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, exc):
        return JSONResponse(status_code=422, content={"error": "INVALID_CONTEXT_QUERY"})

    @app.middleware("http")
    async def private_response(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/api/environmental/v1/health")
    async def health():
        return {
            "status": "ok",
            "service": "earthsync-environmental-context",
            "upstream_checked": False,
        }

    @app.post("/api/environmental/v1/context", response_model=ContextResponse)
    async def context(query: ContextQuery, request: Request):
        if request.query_params:
            raise RequestValidationError([])
        return await request.app.state.service.context(query)

    return app


app = create_app()
