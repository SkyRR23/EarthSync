import json

import httpx
import pytest
from fastapi.testclient import TestClient

from earthsync import chat
from earthsync.api import create_app
from earthsync.chat import GroqChat

FARM = {
    "crop": "Rice",
    "farm size": "About 5.7 acres",
    "rain last 7 days (NASA)": "58 mm, more than usual",
    "forecast tomorrow": "Rain likely, about 6 mm",
    "nested": {"ignored": True},
}


def post(handler, body):
    seen = {}

    def wrapped(request):
        seen["req"] = request
        return handler(request)

    bot = GroqChat(client=httpx.AsyncClient(transport=httpx.MockTransport(wrapped)))
    with TestClient(create_app(chat_bot=bot)) as c:
        return c.post("/api/v1/chat", json=body), seen


def reply(text, status=200):
    return httpx.Response(status, json={"choices": [{"message": {"content": text}}]})


@pytest.fixture(autouse=True)
def key(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "test-key")


def test_answers_with_the_farm_facts_in_the_prompt():
    body = {
        "messages": [
            {"role": "user", "content": "Hi"},
            {"role": "assistant", "content": "Hello!"},
            {"role": "user", "content": "Should I water today?"},
        ],
        "farm": FARM,
    }
    r, seen = post(lambda _: reply("<think>x</think> Rain is likely tomorrow."), body)
    assert r.status_code == 200
    assert r.json()["reply"] == "Rain is likely tomorrow."
    assert r.json()["model"] == chat.CHAT_MODEL
    sent = json.loads(seen["req"].content)
    assert seen["req"].headers["authorization"] == "Bearer test-key"
    system = sent["messages"][0]["content"]
    assert "Never invent numbers" in system
    assert "- crop: Rice" in system
    assert "- forecast tomorrow: Rain likely, about 6 mm" in system
    assert "nested" not in system
    assert [m["role"] for m in sent["messages"][1:]] == ["user", "assistant", "user"]


def test_only_recent_turns_are_sent():
    msgs = [{"role": "user", "content": f"q{i}"} for i in range(30)]
    _, seen = post(lambda _: reply("ok"), {"messages": msgs})
    sent = json.loads(seen["req"].content)
    assert len(sent["messages"]) == 1 + chat.MAX_TURNS
    assert sent["messages"][-1]["content"] == "q29"


@pytest.mark.parametrize(
    "status, code, http",
    [(429, "ai_busy", 503), (401, "ai_key_rejected", 502), (500, "ai_error", 503)],
)
def test_groq_errors(status, code, http):
    r, _ = post(
        lambda _: httpx.Response(status, json={}),
        {"messages": [{"role": "user", "content": "hi"}]},
    )
    assert r.status_code == http
    assert r.json()["error"]["code"] == code


def test_bad_requests():
    for body in [
        {"messages": []},
        {"messages": [{"role": "system", "content": "x"}]},
        {"messages": [{"role": "user", "content": "x" * 2001}]},
        {
            "messages": [
                {"role": "user", "content": "q"},
                {"role": "assistant", "content": "a"},
            ]
        },
    ]:
        r, seen = post(lambda _: reply("x"), body)
        assert r.status_code == 400, body
        assert "req" not in seen


def test_no_key_means_not_set_up(monkeypatch):
    monkeypatch.delenv("GROQ_API_KEY")
    r, seen = post(
        lambda _: reply("x"), {"messages": [{"role": "user", "content": "hi"}]}
    )
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "not_configured"
    assert "req" not in seen
