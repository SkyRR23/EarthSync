import base64
import json

import httpx
import pytest
from fastapi.testclient import TestClient

from earthsync import soil
from earthsync.api import create_app
from earthsync.soil import GroqSoilEstimator

PHOTO = base64.b64encode(b"\xff\xd8\xff\xe0" + b"x" * 64).decode()
BODY = {
    "photos": [PHOTO],
    "answers": {"ribbon": "medium", "feel": "smooth", "signs": ["cracks"]},
}


def reply(content, status=200, finish="stop"):
    return httpx.Response(
        status,
        json={"choices": [{"message": {"content": content}, "finish_reason": finish}]},
    )


def post(handler, body=BODY):
    seen = {}

    def wrapped(request):
        seen["request"] = request
        return handler(request)

    est = GroqSoilEstimator(
        client=httpx.AsyncClient(transport=httpx.MockTransport(wrapped))
    )
    with TestClient(create_app(soil_estimator=est)) as c:
        return c.post("/api/v1/soil/estimate", json=body), seen


@pytest.fixture(autouse=True)
def key(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "test-key")


def test_sends_photos_and_answers_reads_the_estimate():
    answer = {
        "soil_class": "silty_clay_loam",
        "confidence": "medium",
        "photo_usable": True,
        "signs_seen": ["cracks", "made_up_sign"],
        "reason": "Medium ribbon, smooth feel, cracks on top.",
    }
    r, seen = post(lambda _: reply("<think>looking</think>" + json.dumps(answer)))
    body = r.json()
    assert r.status_code == 200
    assert body["source"] == "ai_estimate"
    assert body["model"] == soil.GROQ_MODEL
    assert body["soil_class"] == "silty_clay_loam"
    assert body["signs_seen"] == ["cracks"]  # unknown signs dropped
    assert body["hand_test"] == "silty_clay_loam"

    req = seen["request"]
    assert str(req.url) == soil.GROQ_URL
    assert req.headers["authorization"] == "Bearer test-key"
    sent = json.loads(req.content)
    assert sent["response_format"] == {"type": "json_object"}
    parts = sent["messages"][1]["content"]
    assert parts[0]["image_url"]["url"] == f"data:image/jpeg;base64,{PHOTO}"
    assert "a medium ribbon" in parts[-1]["text"]
    assert "silty_clay_loam" in sent["messages"][0]["content"]


def test_soil_type_outside_the_12_is_rejected():
    bad = {
        "soil_class": "peat",
        "confidence": "high",
        "photo_usable": True,
        "signs_seen": [],
        "reason": "x",
    }
    r, _ = post(lambda _: reply(json.dumps(bad)))
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "ai_bad_answer"


@pytest.mark.parametrize(
    "status, code, http",
    [(401, "ai_key_rejected", 502), (429, "ai_busy", 503), (500, "ai_error", 503)],
)
def test_groq_errors(status, code, http):
    r, _ = post(lambda _: httpx.Response(status, json={"error": {}}))
    assert r.status_code == http
    assert r.json()["error"]["code"] == code


def test_cut_off_answer_is_retryable():
    r, _ = post(lambda _: reply('{"soil_class": "lo', finish="length"))
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "ai_incomplete"


def test_no_key_means_not_set_up(monkeypatch):
    monkeypatch.delenv("GROQ_API_KEY")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    r, seen = post(lambda _: reply("{}"))
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "not_configured"
    assert "request" not in seen


def test_groq_is_used_when_its_key_is_set(monkeypatch):
    assert isinstance(soil._default_estimator(), GroqSoilEstimator)
    monkeypatch.delenv("GROQ_API_KEY")
    assert not isinstance(soil._default_estimator(), GroqSoilEstimator)
