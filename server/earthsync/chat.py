"""EarthSync farm chat: a farmer asks, Groq answers from the farm's own data.

The app sends the conversation plus a short "farm facts" summary it already
shows (crop, soil, weather, NASA, tasks). The model is told to use only those
facts and general good practice, never to invent numbers, and to say when it
does not know. The key stays here (GROQ_API_KEY, Secret Manager).
"""

from __future__ import annotations

import json
import os
from typing import Literal, Optional

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, ValidationError

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
CHAT_MODEL = os.environ.get("CHAT_MODEL", "openai/gpt-oss-120b")
MAX_TURNS = 16

SYSTEM = """You are EarthSync, a friendly farm helper for smallholder farmers in Myanmar.

How to answer:
- Plain, simple English. Short: at most 6 sentences or 5 short bullet points.
- Use the FARM FACTS below and general, widely accepted farming practice.
- Never invent numbers: no yields, prices, fertiliser or pesticide doses, dates
  or weather values that are not in the facts. If a number is needed and not
  given, say you do not know it and how the farmer could find out.
- The facts come from NASA data, a weather forecast and the farmer's answers.
  NASA and forecast values are for the wider area, not measured on the farm.
- For pesticides, chemicals or animal medicine: give only general safe advice
  and tell them to follow the product label and ask the local agriculture
  extension office.
- If the question is not about farming, the farm, weather or the app, say
  kindly that you can only help with the farm.
- When the facts say something is unknown, say it is unknown. Do not guess.
"""

router = APIRouter()


class Turn(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2000)


class ChatRequest(BaseModel):
    messages: list[Turn] = Field(min_length=1, max_length=40)
    farm: dict[str, object] = Field(default_factory=dict)


class NotConfigured(Exception):
    pass


class ChatFailed(Exception):
    def __init__(self, code: str, retryable: bool):
        super().__init__(code)
        self.code, self.retryable = code, retryable


def farm_facts(farm: dict) -> str:
    """The app's facts as short lines; long or odd values are dropped."""
    lines = []
    for k, v in list(farm.items())[:30]:
        if v is None or isinstance(v, (dict, list)):
            continue
        text = str(v).strip()
        if text and len(text) <= 300 and len(str(k)) <= 60:
            lines.append(f"- {k}: {text}")
    return "\n".join(lines) or "- (no farm facts were sent)"


class GroqChat:
    def __init__(self, client: Optional[httpx.AsyncClient] = None):
        self._client = client
        self.model = CHAT_MODEL

    async def reply(self, req: ChatRequest) -> str:
        key = os.environ.get("GROQ_API_KEY")
        if not key:
            raise NotConfigured()
        turns = req.messages[-MAX_TURNS:]
        body = {
            "model": self.model,
            "temperature": 0.3,
            "max_completion_tokens": 1024,
            "messages": [
                {
                    "role": "system",
                    "content": SYSTEM + "\nFARM FACTS:\n" + farm_facts(req.farm),
                },
                *({"role": t.role, "content": t.content} for t in turns),
            ],
        }
        client = self._client or httpx.AsyncClient(
            timeout=httpx.Timeout(60, connect=10)
        )
        try:
            r = await client.post(
                GROQ_URL, headers={"Authorization": f"Bearer {key}"}, json=body
            )
        except (httpx.TimeoutException, httpx.TransportError) as e:
            raise ChatFailed("ai_unreachable", True) from e
        finally:
            if self._client is None:
                await client.aclose()
        if r.status_code == 429:
            raise ChatFailed("ai_busy", True)
        if r.status_code in (401, 403):
            raise ChatFailed("ai_key_rejected", False)
        if r.status_code >= 500:
            raise ChatFailed("ai_error", True)
        if r.status_code != 200:
            raise ChatFailed("ai_error", False)
        try:
            choice = r.json()["choices"][0]
            text = (choice["message"].get("content") or "").strip()
        except (KeyError, IndexError, TypeError, ValueError) as e:
            raise ChatFailed("ai_bad_answer", True) from e
        if "</think>" in text:
            text = text.rsplit("</think>", 1)[1].strip()
        if not text:
            raise ChatFailed("ai_empty", True)
        return text[:4000]


_default = GroqChat()


def _error(status: int, code: str, message: str, retryable: bool) -> JSONResponse:
    return JSONResponse(
        status_code=status,
        content={
            "status": "error",
            "error": {"code": code, "message": message, "retryable": retryable},
        },
    )


@router.post("/api/v1/chat")
async def chat(request: Request):
    try:
        body = ChatRequest.model_validate(await request.json())
    except (ValidationError, json.JSONDecodeError, ValueError):
        return _error(400, "invalid_request", "The message could not be read.", False)
    if body.messages[-1].role != "user":
        return _error(400, "invalid_request", "The last message must be yours.", False)
    bot = getattr(request.app.state, "chat_bot", None) or _default
    try:
        text = await bot.reply(body)
    except NotConfigured:
        return _error(503, "not_configured", "The farm chat is not set up yet.", False)
    except ChatFailed as e:
        return _error(
            503 if e.retryable else 502,
            e.code,
            "The farm chat could not answer. Try again.",
            e.retryable,
        )
    return {
        "status": "success",
        "reply": text,
        "model": getattr(bot, "model", CHAT_MODEL),
        "note": "AI answer from your farm data; check important decisions locally.",
    }
