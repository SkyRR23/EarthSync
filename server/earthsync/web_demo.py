"""Local demo host: Flutter web + NASA backend + native Rust engine."""

import asyncio
import hashlib
import json
import os
from pathlib import Path

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from .api import create_app
from .errors import ServiceError
from .assistant.api import router as assistant_router
from .environmental.models import ContextQuery, ContextResponse
from .evidence.models import TimelineQuery
from .evidence.satellite import HlsAdapter, RtcS1Adapter
from .evidence.timeline import build_timeline

ROOT = Path(__file__).resolve().parents[2]
ENGINE = (
    ROOT
    / "engine/target/debug/examples"
    / ("web_engine.exe" if os.name == "nt" else "web_engine")
)


class DemoStaticFiles(StaticFiles):
    async def get_response(self, path, scope):
        response = await super().get_response(path, scope)
        response.headers["Cache-Control"] = "no-store"
        return response


def validate_engine_output(output, version):
    """Check the existing envelope without translating or replacing Rust results."""
    try:
        result = json.loads(output)
        if not isinstance(result, dict):
            raise ValueError
        if result.get("status") == "error":
            error = result["error"]
            if version == "v03":
                if (
                    result["schema_version"] != "earthsync.engine.v0.3.0"
                    or error["status"] != "input_or_source_validation_failure"
                    or not isinstance(error["path"], str)
                    or not isinstance(error["message"], str)
                ):
                    raise ValueError
                return result
            if not (
                isinstance(error, dict)
                and isinstance(error.get("code"), str)
                and isinstance(error.get("message"), str)
                and type(error.get("retryable")) is bool
            ):
                raise ValueError
        elif result.get("status") == "success":
            data = result["data"]
            if version == "v03":
                if (
                    data["schema_version"] != "earthsync.engine.v0.3.0"
                    or type(data["software_test_only"]) is not bool
                    or not isinstance(data["context"], dict)
                    or not all(
                        isinstance(data[key], list)
                        for key in (
                            "summaries",
                            "findings",
                            "candidates",
                            "limitations",
                        )
                    )
                ):
                    raise ValueError
                json.dumps(result, allow_nan=False)
                return result
            if version == "v02":
                if data["schema_version"] != "0.2-provisional":
                    raise ValueError
                data = data["integration"]
            if data["data_mode"] not in {"supplied_data", "synthetic_demo"} or not all(
                isinstance(data[key], dict)
                for key in ("field", "environment", "climate", "rotations")
            ):
                raise ValueError
        else:
            raise ValueError
        # JSONResponse rejects NaN/infinity even though json.loads accepts them.
        json.dumps(result, allow_nan=False)
        return result
    except (ValueError, TypeError, KeyError, UnicodeError, RecursionError):
        raise ServiceError(
            "ENGINE_INVALID_RESPONSE",
            "Rust returned an unreadable or unexpected response envelope.",
        ) from None


def create_demo_app(
    engine=ENGINE,
    static_dir=ROOT / "app/build/web",
    provider=None,
    context_service=None,
    evidence_store=None,
    evidence_token=None,
):
    app = create_app(provider=provider, context_service=context_service)
    app.title = "EarthSync integrated local demo"
    app.include_router(assistant_router)
    slots = asyncio.Semaphore(2)

    # This is a private single-workspace demo, not account/farm ownership.
    # Never publish a token in Flutter assets, URLs, diagnostics or access logs.
    token = evidence_token or os.environ.get("EARTHSYNC_EVIDENCE_TOKEN")
    if not token and os.environ.get("EARTHSYNC_EVIDENCE_TOKEN_FILE"):
        from .demo_workspace import read_token

        token = read_token(os.environ["EARTHSYNC_EVIDENCE_TOKEN_FILE"])
    if token:
        from .evidence.app import create_app as create_evidence_app

        app.mount(
            "/api/evidence",
            create_evidence_app(
                store=evidence_store,
                token=token,
                prefix="/v1",
                require_secure_transport=True,
            ),
        )

    @app.get("/api/demo/capabilities")
    async def capabilities():
        return {
            "photo_workspace": "private_local_demo" if token else "disabled",
            "identity": "no_production_accounts",
            "upstream_checked": False,
        }

    @app.post("/api/environmental/v1/context", response_model=ContextResponse)
    async def environmental(query: ContextQuery, request: Request):
        if request.query_params:
            raise RequestValidationError([])
        return await request.app.state.context_service.context(query)

    @app.get("/api/environmental/v1/health")
    async def environmental_health():
        return {"status": "ok", "upstream_checked": False}

    @app.post("/api/satellite/v1/timeline")
    async def satellite(query: TimelineQuery):
        # Public availability only. Private photos require the workspace token.
        return await build_timeline(query, [], [HlsAdapter(), RtcS1Adapter()])

    from .demo_middleware import DemoApiMiddleware

    app.add_middleware(DemoApiMiddleware)

    async def run_engine(body, version):
        if not Path(engine).is_file():
            raise ServiceError(
                "ENGINE_CONFIGURATION",
                "Build the web_engine Rust example before starting this service.",
                503,
            )
        args = [str(engine)] + ([f"--{version}"] if version in {"v02", "v03"} else [])
        try:
            await asyncio.wait_for(slots.acquire(), 5)
        except TimeoutError:
            raise ServiceError(
                "ENGINE_BUSY", "Rust workers are busy; retry later.", 503, True
            ) from None
        try:
            try:
                process = await asyncio.create_subprocess_exec(
                    *args,
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
            except (OSError, NotImplementedError):
                raise ServiceError(
                    "ENGINE_CONFIGURATION",
                    "Cannot launch the compiled Rust executable. Check the build, permissions and Python event loop.",
                    503,
                ) from None
            try:
                output, _ = await asyncio.wait_for(process.communicate(body), 20)
            except (TimeoutError, asyncio.CancelledError) as exc:
                if process.returncode is None:
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass
                # Resume draining pipes after cancelled communicate(), so wait()
                # cannot hang behind a full stdout/stderr pipe after termination.
                await process.communicate()
                await process.wait()
                if isinstance(exc, asyncio.CancelledError):
                    raise
                raise ServiceError(
                    "ENGINE_TIMEOUT", "Rust execution exceeded 20 seconds.", 504, True
                ) from None
            if process.returncode:
                raise ServiceError(
                    "ENGINE_FAILED",
                    "Rust exited unsuccessfully. Rebuild the executable and check its inputs.",
                )
            return validate_engine_output(output, version)
        finally:
            slots.release()

    @app.post("/api/v1/diagnostics/integration")
    async def integration_diagnostic(request: Request):
        evidence = await app.state.diagnostic_nasa(request)
        # No crop profiles or recommendations. This tests climate integration only.
        document = {
            "data_mode": "supplied_data",
            "field": {
                "field_id": "public-diagnostic-point",
                "latitude": evidence.environment.latitude,
                "longitude": evidence.environment.longitude,
                "current_crop": "",
                "irrigation_available": None,
            },
            "soil": {"texture": None, "drainage": None},
            "environment": evidence.environment.model_dump(),
            "crop_references": {"sources": [], "profiles": []},
            "scenarios": [],
        }
        result = await run_engine(json.dumps(document).encode(), "integration")
        if result["status"] != "success":
            raise ServiceError(
                "ENGINE_FAILED",
                "Rust rejected the validated diagnostic climate request.",
            )
        return {
            "schema_version": "1.0-diagnostic",
            "status": "success",
            "mode": "live_http",
            "cache_used": False,
            "checks": {
                "nasa_transport": "passed",
                "merra2_validation": "passed",
                "daily_coverage": "complete",
                "rust_execution": "passed",
            },
            "engine_sha256": hashlib.sha256(Path(engine).read_bytes()).hexdigest(),
        }

    @app.get("/api/demo/captured-climate")
    async def captured_climate():
        return json.loads(
            (ROOT / "server/examples/nasa_power_real.json").read_text(encoding="utf-8")
        )

    @app.get("/api/demo/synthetic-v02")
    async def synthetic_v02():
        return json.loads(
            (ROOT / "engine/tests/fixtures/synthetic_v02_request.json").read_text(
                encoding="utf-8"
            )
        )

    @app.get("/api/demo/synthetic-v03")
    async def synthetic_v03():
        return json.loads(
            (ROOT / "engine/tests/fixtures/v03/synthetic_request.json").read_text(
                encoding="utf-8"
            )
        )

    @app.post(
        "/api/engine/{version}",
        openapi_extra={
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {"type": "object"}}},
            }
        },
    )
    async def analyze(version: str, request: Request):
        if version not in {"integration", "v02", "v03"}:
            raise ServiceError("UNKNOWN_INTERFACE", "Unknown engine interface.", 404)
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 2_000_000:
                raise ServiceError(
                    "REQUEST_TOO_LARGE", "Request exceeds the 2 MB demo limit.", 413
                )
        try:
            document = json.loads(body)
        except (ValueError, UnicodeError, RecursionError):
            raise ServiceError(
                "INVALID_INPUT", "Provide a UTF-8 JSON object.", 422
            ) from None
        if not isinstance(document, dict):
            raise ServiceError("INVALID_INPUT", "Provide a JSON object.", 422)
        return JSONResponse(await run_engine(bytes(body), version))

    from .catalog_adapter import router as catalog_router

    app.include_router(catalog_router)

    # Reserve API paths before the static host so missing APIs never serve HTML.
    @app.api_route(
        "/api/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    )
    async def unknown_api(path: str):
        raise ServiceError(
            "UNKNOWN_API", "This API is unavailable or not configured.", 404
        )

    if Path(static_dir).is_dir():
        app.mount("/", DemoStaticFiles(directory=static_dir, html=True), name="flutter")
    return app


app = create_demo_app()
