"""Dedicated research API. Never mounted into the farmer app or master-token API."""

import asyncio
import os
import time
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

from fastapi import FastAPI, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import Field
from starlette.concurrency import run_in_threadpool

from earthsync.evidence.images import MAX_UPLOAD_BYTES, sanitize_image

from .retrieval import EvidenceIndex, EvidenceQuery
from .soil import LabConfirmation, LocalOCR, StrictModel, soil_context
from .multimodal import image_analysis, extract_report
from .vision import ImageRequest, LabAssistRequest, configured_vision
from .storage import ResearchError, ResearchStore

PREFIX = "/api/research/v1"
ROUTE_SCOPES = {
    "/photos": {"post": ["photo:upload"]},
    "/photos/{photo_id}/image": {"get": ["photo:read"]},
    "/photos/{photo_id}": {"delete": ["photo:delete"]},
    "/photos/{photo_id}/analyze": {"post": ["photo:analyze"]},
    "/lab-reports/extract": {"post": ["lab:extract"]},
    "/lab-reports/{report_id}": {"get": ["lab:extract"]},
    "/lab-reports/{report_id}/confirm": {"post": ["lab:confirm"]},
    "/crops/search": {"post": ["crop:evidence:read"]},
    "/crops/evidence": {"post": ["crop:evidence:read"]},
    "/crops/compare": {"post": ["crop:evidence:read"]},
    "/soil/context": {"post": ["soil:reference:read"]},
}


def error_response(code, status):
    return JSONResponse(
        {"error": {"code": code, "retryable": status in (429, 503, 504)}},
        status_code=status,
    )


class Boundary:
    """Admission, authentication and size checks run before JSON decoding."""

    def __init__(self, app, *, store, hosts, origins, require_https, rate_limit):
        self.app, self.store = app, store
        self.hosts, self.origins, self.require_https = hosts, origins, require_https
        self.rate_limit = rate_limit
        self.slots = asyncio.Semaphore(4)
        self.window, self.attempts = 0, 0

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        request = Request(scope)
        headers = {
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
            "referrer-policy": "no-referrer",
        }

        async def guarded_send(message):
            if message["type"] == "http.response.start":
                message["headers"] = list(message.get("headers", [])) + [
                    (k.encode(), v.encode()) for k, v in headers.items()
                ]
            await send(message)

        async def reject(code, status):
            await error_response(code, status)(scope, receive, guarded_send)

        if request.url.hostname not in self.hosts:
            return await reject("HOST_FORBIDDEN", 403)
        if self.require_https and scope["scheme"] != "https":
            return await reject("HTTPS_REQUIRED", 403)
        origin = request.headers.get("origin")
        if origin and origin not in self.origins:
            return await reject("ORIGIN_FORBIDDEN", 403)
        window = int(time.monotonic() // 60)
        if self.window != window:
            self.window, self.attempts = window, 0
        self.attempts += 1
        if self.attempts > 600:
            return await reject("RATE_LIMIT", 429)
        if request.method == "OPTIONS":
            return await self.app(scope, receive, guarded_send)
        principal = None
        try:
            if request.url.path not in (
                "/docs",
                "/openapi.json",
                "/docs/oauth2-redirect",
            ):
                auth = request.headers.get("authorization", "")
                token = auth[7:] if auth.startswith("Bearer ") else ""
                principal = await run_in_threadpool(
                    self.store.authenticate, token, self.rate_limit
                )
                scope.setdefault("state", {})["principal"] = principal
            limit = (
                MAX_UPLOAD_BYTES
                if request.url.path == PREFIX + "/photos" and request.method == "POST"
                else 64 * 1024
            )
            declared = request.headers.get("content-length")
            if declared is not None and (
                not declared.isdecimal() or int(declared) > limit
            ):
                return await reject("REQUEST_TOO_LARGE", 413)
            async with asyncio.timeout(45):
                async with self.slots:
                    body = bytearray()
                    while True:
                        part = await receive()
                        if part["type"] == "http.disconnect":
                            return
                        body.extend(part.get("body", b""))
                        if len(body) > limit:
                            return await reject("REQUEST_TOO_LARGE", 413)
                        if not part.get("more_body", False):
                            break
                    delivered = False

                    async def buffered_receive():
                        nonlocal delivered
                        if delivered:
                            return await receive()
                        delivered = True
                        return {
                            "type": "http.request",
                            "body": bytes(body),
                            "more_body": False,
                        }

                    # Audit only fixed method/route-template metadata in endpoint handlers.
                    await self.app(scope, buffered_receive, guarded_send)
        except ResearchError as exc:
            await run_in_threadpool(
                self.store.audit,
                principal["id"] if principal else None,
                "request.denied",
                None,
                exc.status,
            )
            await reject(exc.code, exc.status)
        except TimeoutError:
            await reject("TIMEOUT", 504)


class Search(StrictModel):
    query: str = Field(default="", max_length=150)


class Compare(StrictModel):
    crops: list[str] = Field(min_length=2, max_length=4)
    question: str = Field(default="", max_length=1000)
    region: str | None = Field(default=None, max_length=150)
    cultivar: str | None = Field(default=None, max_length=150)
    system: str | None = Field(default=None, max_length=150)


class PhotoAction(ImageRequest):
    farm_id: UUID


class Extract(LabAssistRequest):
    farm_id: UUID
    photo_id: UUID


class Context(StrictModel):
    farm_id: UUID
    report_ids: list[UUID] = Field(default_factory=list, max_length=20)
    farmer_reports: list[str] = Field(default_factory=list, max_length=20)


def create_app(
    *,
    store,
    index=None,
    ocr=None,
    vision=None,
    allowed_hosts=("localhost", "127.0.0.1"),
    allowed_origins=(),
    require_https=True,
    rate_limit=60,
):
    if not allowed_hosts or any(h == "*" or "/" in h for h in allowed_hosts):
        raise ValueError("Require exact allowed hosts")
    for origin in allowed_origins:
        parsed = urlsplit(origin)
        if (
            parsed.scheme not in ("http", "https")
            or not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.path
            or parsed.query
            or parsed.fragment
            or "*" in origin
            or (
                parsed.scheme == "http"
                and parsed.hostname not in ("localhost", "127.0.0.1", "::1")
            )
        ):
            raise ValueError(
                "Require exact HTTPS origins, or HTTP loopback development origins"
            )
    index, ocr = index or EvidenceIndex(), ocr or LocalOCR()
    app = FastAPI(
        title="EarthSync Research API",
        version="1.0.0",
        redoc_url=None,
        swagger_ui_parameters={"persistAuthorization": False},
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(allowed_origins),
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
        allow_credentials=False,
    )
    app.add_middleware(
        Boundary,
        store=store,
        hosts=allowed_hosts,
        origins=allowed_origins,
        require_https=require_https,
        rate_limit=rate_limit,
    )

    # Swagger uses this bearer scheme; authentication itself is enforced before body parsing.
    from fastapi.openapi.utils import get_openapi

    def openapi():
        schema = get_openapi(title=app.title, version=app.version, routes=app.routes)
        schema.setdefault("components", {})["securitySchemes"] = {
            "ResearchBearer": {"type": "http", "scheme": "bearer"}
        }
        schema["security"] = [{"ResearchBearer": []}]
        schema["components"]["schemas"]["ResearchError"] = {
            "type": "object",
            "required": ["error"],
            "properties": {
                "error": {
                    "type": "object",
                    "required": ["code", "retryable"],
                    "properties": {
                        "code": {"type": "string"},
                        "retryable": {"type": "boolean"},
                    },
                }
            },
        }
        for path, methods in schema["paths"].items():
            for method, operation in methods.items():
                operation["x-required-scopes"] = ROUTE_SCOPES.get(
                    path.removeprefix(PREFIX), {}
                ).get(method, [])
                for status in (401, 403, 404, 413, 422, 429, 507):
                    operation["responses"][str(status)] = {
                        "description": "Research API error; private input is never echoed",
                        "content": {
                            "application/json": {
                                "schema": {"$ref": "#/components/schemas/ResearchError"}
                            }
                        },
                    }
        return schema

    app.openapi = openapi

    @app.exception_handler(ResearchError)
    async def research_error(request, exc):
        await run_in_threadpool(
            store.audit,
            getattr(request.state, "principal", {}).get("id"),
            "request.denied",
            None,
            exc.status,
        )
        return error_response(exc.code, exc.status)

    @app.exception_handler(RequestValidationError)
    async def invalid(request, exc):
        return error_response(
            "INVALID_INPUT", 422
        )  # Never echo OCR, credentials or private fields.

    def permit(request, scope):
        principal = request.state.principal
        store.require(principal, scope)
        return principal

    @app.get(PREFIX + "/health")
    def health(request: Request):
        return {
            "status": "ok",
            "version": "v1",
            "recommendation_eligible": False,
            "vision_configured": vision is not None and vision.supports_images,
            "ocr_available": bool(ocr.executable),
        }

    @app.post(PREFIX + "/crops/search")
    def search(value: Search, request: Request):
        principal = permit(request, "crop:evidence:read")
        store.audit(principal["id"], "crop.search")
        return {"crops": index.search(value.query), "recommendation_eligible": False}

    @app.post(PREFIX + "/crops/evidence")
    def evidence(value: EvidenceQuery, request: Request):
        principal = permit(request, "crop:evidence:read")
        store.audit(principal["id"], "crop.evidence")
        return index.retrieve(value)

    @app.post(PREFIX + "/crops/compare")
    def compare(value: Compare, request: Request):
        principal = permit(request, "crop:evidence:read")
        store.audit(principal["id"], "crop.compare")
        return {
            "recommendation_eligible": False,
            "ranking": None,
            "crops": [
                index.retrieve(
                    EvidenceQuery(crop=c, **value.model_dump(exclude={"crops"}))
                )
                for c in value.crops
            ],
        }

    @app.post(PREFIX + "/photos", status_code=201)
    async def upload(request: Request, farm_id: UUID):
        principal = permit(request, "photo:upload")
        store.farm(principal, farm_id)
        try:
            image = await run_in_threadpool(
                sanitize_image,
                await request.body(),
                request.headers.get("content-type", ""),
            )
        except ValueError as exc:
            raise ResearchError("INVALID_IMAGE", 422) from exc
        return await run_in_threadpool(store.save_photo, principal, farm_id, image)

    @app.get(PREFIX + "/photos/{photo_id}/image")
    def image(photo_id: UUID, farm_id: UUID, request: Request):
        principal = permit(request, "photo:read")
        _, pixels = store.photo(principal, farm_id, photo_id)
        store.audit(principal["id"], "photo.read", str(photo_id))
        return Response(
            pixels,
            media_type="image/png",
            headers={
                "Content-Security-Policy": "default-src 'none'; sandbox",
                "Content-Disposition": 'inline; filename="research-photo.png"',
            },
        )

    @app.delete(PREFIX + "/photos/{photo_id}", status_code=204)
    def delete(photo_id: UUID, farm_id: UUID, request: Request):
        principal = permit(request, "photo:delete")
        store.delete_photo(principal, farm_id, photo_id)
        return Response(status_code=204)

    @app.post(PREFIX + "/photos/{photo_id}/analyze")
    def analyze(photo_id: UUID, value: PhotoAction, request: Request):
        principal = permit(request, "photo:analyze")
        _, pixels = store.photo(principal, value.farm_id, photo_id)
        result = image_analysis(
            photo_id,
            pixels,
            value=ImageRequest.model_validate(value.model_dump(exclude={"farm_id"})),
            index=index,
            provider=vision,
        )
        store.audit(principal["id"], "photo.analyzed", str(photo_id))
        return result

    @app.post(PREFIX + "/lab-reports/extract", status_code=201)
    def extract(value: Extract, request: Request):
        principal = permit(request, "lab:extract")
        _, pixels = store.photo(principal, value.farm_id, value.photo_id)
        return store.save_report(
            principal,
            value.farm_id,
            value.photo_id,
            extract_report(pixels, ocr=ocr, value=value, provider=vision),
        )

    @app.get(PREFIX + "/lab-reports/{report_id}")
    def report(report_id: UUID, farm_id: UUID, request: Request):
        principal = permit(request, "lab:extract")
        return store.report(principal, farm_id, report_id)

    @app.post(PREFIX + "/lab-reports/{report_id}/confirm")
    def confirm(
        report_id: UUID, farm_id: UUID, value: LabConfirmation, request: Request
    ):
        principal = permit(request, "lab:confirm")
        return store.report(
            principal, farm_id, report_id, value.model_dump(mode="json")
        )

    @app.post(PREFIX + "/soil/context")
    def context(value: Context, request: Request):
        principal = permit(request, "soil:reference:read")
        store.farm(principal, value.farm_id)
        reports = []
        if value.report_ids:
            store.require(principal, "lab:extract")
            reports = [
                store.report(principal, value.farm_id, ident)
                for ident in value.report_ids
            ]
        if any(len(text) > 1000 for text in value.farmer_reports):
            raise ResearchError("INVALID_INPUT")
        store.audit(principal["id"], "soil.context")
        return {
            **soil_context(farmer_reported=value.farmer_reports, laboratory=reports),
            "modeled_reference_status": "unavailable: separate research tenant has no verified EarthSync farm linkage",
        }

    return app


def app_factory():
    local = os.getenv("EARTHSYNC_RESEARCH_LOCAL") == "1"
    return create_app(
        store=ResearchStore(Path(os.environ["EARTHSYNC_RESEARCH_DIR"])),
        vision=configured_vision(),
        allowed_hosts=tuple(
            filter(
                None,
                os.getenv("EARTHSYNC_RESEARCH_HOSTS", "localhost,127.0.0.1").split(","),
            )
        ),
        allowed_origins=tuple(
            filter(None, os.getenv("EARTHSYNC_RESEARCH_ORIGINS", "").split(","))
        ),
        require_https=not local,
    )
