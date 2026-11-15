import base64
import json
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from earthsync.api import create_app
from earthsync.soil import ClaudeSoilEstimator, hand_key

JPEG = base64.b64encode(b"\xff\xd8\xff\xe0" + b"0" * 64).decode()
URL = "/api/v1/soil/estimate"


class _Messages:
    def __init__(self, response=None, error=None):
        self.response, self.error, self.calls = response, error, []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.response


def _client_with(response=None, error=None):
    msgs = _Messages(response, error)
    fake = SimpleNamespace(beta=SimpleNamespace(messages=msgs))
    app = create_app(soil_estimator=ClaudeSoilEstimator(client=fake))
    return TestClient(app), msgs


def _answer(**data):
    body = {
        "soil_class": "clay_loam",
        "confidence": "medium",
        "photo_usable": True,
        "signs_seen": ["cracks"],
        "reason": "Medium ribbon and cracks when dry.",
    }
    body.update(data)
    return SimpleNamespace(
        stop_reason="end_turn",
        content=[SimpleNamespace(type="text", text=json.dumps(body))],
    )


def _req(photos=(JPEG, JPEG), ribbon="medium", feel="sticky", signs=("cracks",)):
    return {
        "photos": list(photos),
        "answers": {"ribbon": ribbon, "feel": feel, "signs": list(signs)},
        "latitude": 16.85,
        "longitude": 96.15,
    }


@pytest.mark.parametrize(
    "ribbon,feel,expected",
    [
        ("falls_apart", "unsure", "sand"),
        ("none", "gritty", "loamy_sand"),
        ("none", "sticky", "sandy_loam"),
        ("short", "gritty", "sandy_loam"),
        ("short", "smooth", "silt_loam"),
        ("short", "sticky", "loam"),
        ("medium", "gritty", "sandy_clay_loam"),
        ("medium", "smooth", "silty_clay_loam"),
        ("medium", "unsure", "clay_loam"),
        ("long", "gritty", "sandy_clay"),
        ("long", "smooth", "silty_clay"),
        ("long", "sticky", "clay"),
        ("unsure", "gritty", None),
    ],
)
def test_hand_key(ribbon, feel, expected):
    assert hand_key(ribbon, feel) == expected


def test_photos_and_answers_go_to_claude_and_estimate_comes_back():
    client, msgs = _client_with(_answer())
    r = client.post(URL, json=_req())
    assert r.status_code == 200
    data = r.json()
    assert data["source"] == "ai_estimate"
    assert data["soil_class"] == "clay_loam"
    assert data["hand_test"] == "clay_loam"
    call = msgs.calls[0]
    assert call["model"] == "claude-opus-5-5"
    assert call["fallbacks"] == "default"
    assert call["output_config"]["format"]["type"] == "json_schema"
    content = call["messages"][0]["content"]
    assert [b["type"] for b in content] == ["image", "image", "text"]
    assert "medium ribbon" in content[-1]["text"]
    assert "clay_loam" in content[-1]["text"]


def test_no_photos_returns_the_hand_test_without_calling_ai():
    client, msgs = _client_with(_answer())
    r = client.post(URL, json=_req(photos=(), ribbon="short", feel="smooth"))
    assert r.status_code == 200
    assert r.json()["source"] == "hand_test"
    assert r.json()["soil_class"] == "silt_loam"
    assert msgs.calls == []


def test_refusal_becomes_unknown_not_a_guess():
    refused = SimpleNamespace(stop_reason="refusal", content=[])
    client, _ = _client_with(refused)
    data = client.post(URL, json=_req()).json()
    assert data["soil_class"] == "unknown"
    assert data["confidence"] == "low"


def test_answer_outside_the_soil_list_is_rejected():
    client, _ = _client_with(_answer(soil_class="mud"))
    r = client.post(URL, json=_req())
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "ai_bad_answer"


@pytest.mark.parametrize(
    "photos",
    [
        ["not base64!!"],
        [base64.b64encode(b"GIF89a....").decode()],
        [JPEG, JPEG, JPEG],
    ],
)
def test_bad_photos_are_refused(photos):
    client, msgs = _client_with(_answer())
    r = client.post(URL, json=_req(photos=photos))
    assert r.status_code == 400
    assert msgs.calls == []


def test_without_api_key_the_server_says_not_set_up(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    client = TestClient(create_app(soil_estimator=ClaudeSoilEstimator()))
    r = client.post(URL, json=_req())
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "not_configured"
