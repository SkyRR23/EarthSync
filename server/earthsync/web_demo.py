"""Local demo host: Flutter web + NASA backend + native Rust engine."""

import asyncio
import json
import os
from pathlib import Path

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from .api import create_app

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


def create_demo_app(engine=ENGINE, static_dir=ROOT / "app/build/web"):
    app = create_app()
    slots = asyncio.Semaphore(2)

    @app.get("/api/demo/captured-climate")
    async def captured_climate():
        return json.loads((ROOT / "server/examples/nasa_power_real.json").read_text())

    @app.get("/api/demo/synthetic-v02")
    async def synthetic_v02():
        return json.loads(
            (ROOT / "engine/tests/fixtures/synthetic_v02_request.json").read_text()
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
        if version not in {"integration", "v02"}:
            raise HTTPException(404, "Unknown engine interface")
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 2_000_000:
                raise HTTPException(413, "Request exceeds demo limit")
        try:
            document = json.loads(body)
        except (ValueError, UnicodeError):
            raise HTTPException(422, "Provide a UTF-8 JSON object") from None
        if not isinstance(document, dict):
            raise HTTPException(422, "Provide a JSON object")
        if not Path(engine).is_file():
            raise HTTPException(503, "Build the web_engine Rust example first")
        args = [str(engine)] + (["--v02"] if version == "v02" else [])
        async with slots:
            process = await asyncio.create_subprocess_exec(
                *args,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                output, _ = await asyncio.wait_for(process.communicate(bytes(body)), 20)
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                raise HTTPException(504, "Rust engine timed out") from None
        if process.returncode:
            raise HTTPException(502, "Rust engine process failed")
        return JSONResponse(json.loads(output))

    if Path(static_dir).is_dir():
        app.mount("/", DemoStaticFiles(directory=static_dir, html=True), name="flutter")
    return app


app = create_demo_app()
