"""AI soil estimate for Field Shift: farmer photos + hand-test answers -> soil
texture class, with confidence and the signs seen.

The result is an *estimate* (source ``ai_estimate``), never a lab value. The
hand-texture answers are the strongest evidence; photos add visible signs.
When evidence is weak or conflicting the model must answer ``unknown``.
No photo, answer or location is logged by this module.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
from typing import Literal, Optional, Protocol

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ValidationError, field_validator

MODEL = os.environ.get("SOIL_MODEL", "claude-opus-5-5")

# USDA texture classes (snake_case). Engine v0.3 compares soil categories as
# plain names, so crop profiles must use these same names.
SoilClass = Literal[
    "sand",
    "loamy_sand",
    "sandy_loam",
    "loam",
    "silt_loam",
    "silt",
    "sandy_clay_loam",
    "clay_loam",
    "silty_clay_loam",
    "sandy_clay",
    "silty_clay",
    "clay",
]
SOIL_CLASSES: list[str] = list(SoilClass.__args__)  # type: ignore[attr-defined]

Sign = Literal[
    "cracks",
    "white_crust",
    "grey_spots",
    "stones",
    "dark_topsoil",
    "waterlogged",
    "roots_or_worms",
]
SIGNS: list[str] = list(Sign.__args__)  # type: ignore[attr-defined]

Ribbon = Literal["falls_apart", "none", "short", "medium", "long", "unsure"]
Feel = Literal["gritty", "smooth", "sticky", "unsure"]

MAX_PHOTOS = 2
MAX_PHOTO_BYTES = 3_000_000


def hand_key(ribbon: str, feel: str) -> Optional[str]:
    """Hand-texture key (after Thien 1979), simplified to two answers.

    Ribbon length gives the family (loam / clay loam / clay); gritty or smooth
    gives the sandy or silty member. Returns None when the ribbon is unknown.
    """
    if ribbon == "falls_apart":
        return "sand"
    family = {
        "none": ("loamy_sand", "silt_loam", "sandy_loam"),
        "short": ("sandy_loam", "silt_loam", "loam"),
        "medium": ("sandy_clay_loam", "silty_clay_loam", "clay_loam"),
        "long": ("sandy_clay", "silty_clay", "clay"),
    }.get(ribbon)
    if family is None:
        return None
    gritty, smooth, base = family
    return {"gritty": gritty, "smooth": smooth}.get(feel, base)


class Answers(BaseModel):
    ribbon: Ribbon
    feel: Feel
    signs: list[Sign] = Field(default_factory=list, max_length=len(SIGNS))


class SoilRequest(BaseModel):
    photos: list[str] = Field(default_factory=list, max_length=MAX_PHOTOS)
    answers: Answers
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)

    @field_validator("photos")
    @classmethod
    def _photos_are_images(cls, photos: list[str]) -> list[str]:
        for p in photos:
            raw = _decode(p)
            if len(raw) > MAX_PHOTO_BYTES:
                raise ValueError("photo too large")
            if _media_type(raw) is None:
                raise ValueError("photo must be JPEG or PNG")
        return photos


class SoilEstimate(BaseModel):
    soil_class: Literal[tuple(SOIL_CLASSES + ["unknown"])]  # type: ignore[valid-type]
    confidence: Literal["low", "medium", "high"]
    photo_usable: bool
    signs_seen: list[Sign]
    reason: str = Field(max_length=400)


def _decode(b64: str) -> bytes:
    try:
        return base64.b64decode(b64, validate=True)
    except (binascii.Error, ValueError) as e:
        raise ValueError("photo is not valid base64") from e


def _media_type(raw: bytes) -> Optional[str]:
    if raw[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    return None


SYSTEM = """You help smallholder farmers in Myanmar understand their soil.
You get up to two phone photos (soil on the ground, a squeezed handful) and the
farmer's hand-texture answers. Estimate the USDA soil texture class.

Rules:
- The hand-texture answers are the strongest evidence for texture. Photos add
  what is visible: colour, cracks, white salt crust, grey or blue mottles,
  visible sand grains, stones, roots or worms, standing water.
- Never invent lab values or percentages.
- If the photos are not soil, too dark or too blurry, set photo_usable false and
  rely on the answers.
- If the evidence is weak or the photos clearly contradict the answers, answer
  soil_class "unknown" with confidence "low". Use "high" only when answers and
  photos clearly agree.
- signs_seen: only signs you can see in the photos or that the farmer reported.
- reason: one or two short, plain English sentences for a farmer, no jargon."""

SCHEMA = {
    "type": "object",
    "properties": {
        "soil_class": {"type": "string", "enum": SOIL_CLASSES + ["unknown"]},
        "confidence": {"type": "string", "enum": ["low", "medium", "high"]},
        "photo_usable": {"type": "boolean"},
        "signs_seen": {"type": "array", "items": {"type": "string", "enum": SIGNS}},
        "reason": {"type": "string"},
    },
    "required": ["soil_class", "confidence", "photo_usable", "signs_seen", "reason"],
    "additionalProperties": False,
}

RIBBON_TEXT = {
    "falls_apart": "the soil falls apart and will not make a ball",
    "none": "it makes a ball but no ribbon",
    "short": "a short ribbon, under 2.5 cm",
    "medium": "a medium ribbon, 2.5 to 5 cm",
    "long": "a long ribbon, over 5 cm",
    "unsure": "not sure",
}


class SoilEstimator(Protocol):
    async def estimate(self, req: SoilRequest, hand: Optional[str]) -> SoilEstimate: ...


class NotConfigured(Exception):
    """No AI provider is set up on this server."""


class EstimateFailed(Exception):
    def __init__(self, code: str, retryable: bool):
        super().__init__(code)
        self.code, self.retryable = code, retryable


class ClaudeSoilEstimator:
    """Optional provider: calls Claude with the photos and answers.

    The AI provider is not decided yet, so the ``anthropic`` package is an
    optional extra (``pip install .[claude]``). Without the package or a key the
    endpoint answers ``not_configured`` and the app uses the hand test.
    """

    def __init__(self, client=None):
        self._client = client

    def _get_client(self):
        if self._client is None:
            if not os.environ.get("ANTHROPIC_API_KEY"):
                raise NotConfigured()
            try:
                import anthropic
            except ImportError as e:
                raise NotConfigured() from e
            self._client = anthropic.AsyncAnthropic()
        return self._client

    async def estimate(self, req: SoilRequest, hand: Optional[str]) -> SoilEstimate:
        client = self._get_client()
        content: list[dict] = []
        for p in req.photos:
            content.append(
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": _media_type(_decode(p)),
                        "data": p,
                    },
                }
            )
        a = req.answers
        content.append(
            {
                "type": "text",
                "text": (
                    f"Photos: {len(req.photos)} (first: soil on the ground; second: "
                    "squeezed handful).\n"
                    f"Ribbon test: {RIBBON_TEXT[a.ribbon]}.\n"
                    f"Feel when rubbed wet: {a.feel}.\n"
                    f"Signs the farmer reported: {', '.join(a.signs) or 'none'}.\n"
                    f"Hand-texture key result from these answers: {hand or 'not decided'}."
                ),
            }
        )
        try:
            resp = await client.beta.messages.create(
                model=MODEL,
                max_tokens=16000,
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
                system=SYSTEM,
                output_config={
                    "effort": "medium",
                    "format": {"type": "json_schema", "schema": SCHEMA},
                },
                messages=[{"role": "user", "content": content}],
            )
        except Exception as e:
            raise _provider_error(e) from e

        if resp.stop_reason == "refusal":
            return SoilEstimate(
                soil_class="unknown",
                confidence="low",
                photo_usable=False,
                signs_seen=[],
                reason="We could not check these photos. Your hand test result is shown instead.",
            )
        if resp.stop_reason == "max_tokens":
            raise EstimateFailed("ai_incomplete", True)
        text = next((b.text for b in resp.content if b.type == "text"), None)
        if text is None:
            raise EstimateFailed("ai_empty", True)
        try:
            return SoilEstimate.model_validate(json.loads(text))
        except (json.JSONDecodeError, ValidationError) as e:
            raise EstimateFailed("ai_bad_answer", True) from e


def _provider_error(e: Exception) -> Exception:
    """Map the SDK's typed errors without importing it at module load."""
    if type(e).__module__.split(".")[0] != "anthropic":
        return e
    import anthropic

    if isinstance(e, anthropic.RateLimitError):
        return EstimateFailed("ai_busy", True)
    if isinstance(e, anthropic.APIConnectionError):
        return EstimateFailed("ai_unreachable", True)
    if isinstance(e, anthropic.APIStatusError):
        return EstimateFailed("ai_error", e.status_code >= 500)
    return e


router = APIRouter()
_default_estimator = ClaudeSoilEstimator()


def _error(status: int, code: str, message: str, retryable: bool) -> JSONResponse:
    return JSONResponse(
        status_code=status,
        content={
            "status": "error",
            "error": {"code": code, "message": message, "retryable": retryable},
        },
    )


@router.post("/api/v1/soil/estimate")
async def soil_estimate(request: Request):
    try:
        body = SoilRequest.model_validate(await request.json())
    except (ValidationError, json.JSONDecodeError, ValueError):
        return _error(
            400, "invalid_request", "Photos or answers could not be read.", False
        )

    hand = hand_key(body.answers.ribbon, body.answers.feel)
    estimator: SoilEstimator = (
        getattr(request.app.state, "soil_estimator", None) or _default_estimator
    )
    if not body.photos:
        # Nothing for the AI to look at: the hand test is the answer.
        return {
            "status": "success",
            "source": "hand_test",
            "soil_class": hand or "unknown",
            "confidence": "medium" if hand else "low",
            "photo_usable": False,
            "signs_seen": list(body.answers.signs),
            "reason": "From your hand test.",
            "hand_test": hand,
        }
    try:
        est = await estimator.estimate(body, hand)
    except NotConfigured:
        return _error(
            503, "not_configured", "Photo soil check is not set up yet.", False
        )
    except EstimateFailed as e:
        return _error(
            503 if e.retryable else 502,
            e.code,
            "Photo soil check failed. Try again.",
            e.retryable,
        )

    return {
        "status": "success",
        "source": "ai_estimate",
        "model": MODEL,
        **est.model_dump(),
        "hand_test": hand,
    }
