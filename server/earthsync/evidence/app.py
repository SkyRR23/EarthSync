"""Standalone evidence service. Run factory, do not change existing app routes."""

import asyncio
import hmac
import os
from pathlib import Path
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from .images import MAX_UPLOAD_BYTES, InvalidImage, sanitize_image
from .models import Photo, PhotoInput, TimelineQuery
from .satellite import HlsAdapter, RtcS1Adapter
from .store import PhotoStore, StorageFull
from .timeline import build_timeline

PREFIX = "/api/evidence/v1"


def create_app(store=None, token=None, adapters=None, allowed_origins=None):
    """One bearer token = one private farmer workspace, not multi-tenant auth."""
    token = token or os.environ.get("EARTHSYNC_EVIDENCE_TOKEN")
    if not token or len(token) < 32 or not token.isascii():
        raise ValueError("Set a private ASCII evidence token of at least 32 characters")
    if store is None:
        directory = os.environ.get("EARTHSYNC_EVIDENCE_DIR")
        if not directory:
            raise ValueError(
                "Set EARTHSYNC_EVIDENCE_DIR to an absolute private directory"
            )
        store = PhotoStore(Path(directory))
    adapters = adapters if adapters is not None else [HlsAdapter(), RtcS1Adapter()]

    async def authorize(request: Request):
        authorization = request.headers.get("authorization", "")
        if not hmac.compare_digest(authorization.encode(), f"Bearer {token}".encode()):
            raise HTTPException(401, "Evidence workspace authorization required")

    app = FastAPI(
        title="EarthSync private evidence workspace",
        version="1.0.0",
        dependencies=[Depends(authorize)],
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )
    origins = (
        allowed_origins
        if allowed_origins is not None
        else [
            origin.strip()
            for origin in os.environ.get("EARTHSYNC_EVIDENCE_ORIGINS", "").split(",")
            if origin.strip()
        ]
    )
    if "*" in origins:
        raise ValueError("Evidence CORS requires exact trusted origins")
    if origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=origins,
            allow_methods=["GET", "POST", "PUT", "DELETE"],
            allow_headers=["Authorization", "Content-Type", "X-EarthSync-Metadata"],
        )
    # Bound simultaneous image decoding memory independently of HTTP concurrency.
    slots = asyncio.Semaphore(2)

    @app.middleware("http")
    async def private_responses(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, exc):
        return JSONResponse(
            status_code=422, content={"detail": "Invalid evidence.v1 request"}
        )

    @app.exception_handler(KeyError)
    async def missing_photo(request, exc):
        return JSONResponse(status_code=404, content={"detail": "Photo not found"})

    @app.exception_handler(StorageFull)
    async def storage_full(request, exc):
        return JSONResponse(
            status_code=507, content={"detail": "Evidence storage quota reached"}
        )

    def photo_key(photo_id: str):
        try:
            if str(UUID(photo_id)) != photo_id:
                raise ValueError
        except ValueError:
            raise HTTPException(404, "Photo not found") from None
        return photo_id

    async def read_upload(request):
        header = request.headers.get("x-earthsync-metadata", "")
        if len(header.encode()) > 8192:
            raise HTTPException(422, "Evidence metadata exceeds 8 KiB")
        try:
            metadata = PhotoInput.model_validate_json(header)
        except ValidationError:
            raise HTTPException(422, "Invalid photo metadata") from None
        mime = request.headers.get("content-type", "").lower()
        if mime not in {"image/jpeg", "image/png"}:
            raise HTTPException(415, "Only image/jpeg and image/png are supported")
        declared = request.headers.get("content-length")
        if declared is not None:
            try:
                if int(declared) <= 0:
                    raise HTTPException(422, "Image must be nonempty")
                if int(declared) > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "Image exceeds upload limit")
            except ValueError:
                raise HTTPException(422, "Invalid Content-Length") from None
        raw = bytearray()
        async for chunk in request.stream():
            if len(raw) + len(chunk) > MAX_UPLOAD_BYTES:
                raise HTTPException(413, "Image exceeds 10 MiB")
            raw.extend(chunk)
        try:
            clean = await asyncio.to_thread(sanitize_image, bytes(raw), mime)
        except InvalidImage as exc:
            raise HTTPException(422, str(exc)) from None
        return metadata, clean

    @app.post(f"{PREFIX}/photos", response_model=Photo, status_code=201)
    async def upload(request: Request):
        async with slots:
            metadata, image = await read_upload(request)
            return await asyncio.to_thread(store.save, metadata, image)

    @app.put(f"{PREFIX}/photos/{{photo_id}}", response_model=Photo)
    async def replace(photo_id: str, request: Request):
        photo_key(photo_id)
        await asyncio.to_thread(store.get, photo_id)
        async with slots:
            metadata, image = await read_upload(request)
            return await asyncio.to_thread(store.save, metadata, image, photo_id)

    @app.get(f"{PREFIX}/photos", response_model=list[Photo])
    async def photos():
        return await asyncio.to_thread(store.list)

    @app.get(f"{PREFIX}/photos/{{photo_id}}", response_model=Photo)
    async def photo(photo_id: str):
        return await asyncio.to_thread(store.get, photo_key(photo_id))

    @app.get(f"{PREFIX}/photos/{{photo_id}}/image")
    async def image(photo_id: str):
        data = await asyncio.to_thread(store.image, photo_key(photo_id))
        return Response(
            data,
            media_type="image/png",
            headers={
                "Content-Disposition": 'inline; filename="field-photo.png"',
                "Content-Security-Policy": "default-src 'none'; sandbox",
            },
        )

    @app.delete(f"{PREFIX}/photos/{{photo_id}}", status_code=204)
    async def remove(photo_id: str):
        await asyncio.to_thread(store.delete, photo_key(photo_id))
        return Response(status_code=204)

    @app.post(f"{PREFIX}/timeline")
    async def timeline(query: TimelineQuery):
        return await build_timeline(
            query, await asyncio.to_thread(store.list), adapters
        )

    return app
