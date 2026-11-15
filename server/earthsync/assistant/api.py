"""Opt-in API: uvicorn earthsync.assistant.api:app --port 8001.

An integration owner can mount `router` in the existing backend without changing
any NASA or Rust contracts. This service never fetches provider URLs.
"""

from fastapi import APIRouter, FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .models import ChatRequest, ChatResponse
from .service import explain

router = APIRouter(prefix="/api/assistant/v1", tags=["farmer-assistant"])


@router.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest):
    return explain(request)


def create_assistant_app(allowed_origins=()):
    app = FastAPI(title="EarthSync farmer assistant", version="1.0-proposal")
    if allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(allowed_origins),
            allow_methods=["POST"],
            allow_headers=["Content-Type"],
        )

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, exc):
        # Do not echo location, user text, or raw supplied evidence in errors.
        return JSONResponse(
            status_code=422,
            content={
                "error": {"code": "INVALID_ASSISTANT_CONTEXT", "retryable": False}
            },
        )

    app.include_router(router)
    return app


# Exact local demo origins only; no wildcard credentials or external write actions.
app = create_assistant_app(("http://localhost:8081", "http://127.0.0.1:8081"))
