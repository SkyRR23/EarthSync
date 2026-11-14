import asyncio
import json
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from earthsync import web_demo
from earthsync.web_demo import ENGINE, ROOT, create_demo_app


@pytest.fixture
def client():
    assert ENGINE.is_file(), "Build cargo example web_engine before these tests"
    with TestClient(create_demo_app()) as value:
        yield value


def test_real_rust_integration_and_invalid_request(client):
    request = json.loads(
        (ROOT / "engine/tests/fixtures/synthetic_integration_request.json").read_text()
    )
    response = client.post("/api/engine/integration", json=request)
    assert response.status_code == 200
    result = response.json()
    assert result["status"] == "success"
    assert result["data"]["data_mode"] == "synthetic_demo"
    assert client.post("/api/engine/integration", json={}).json()["status"] == "error"


def test_real_v02_engine_is_available_without_inventing_recommendations(client):
    fixture = client.get("/api/demo/synthetic-v02").json()
    response = client.post("/api/engine/v02", json=fixture)
    assert response.status_code == 200
    assert response.json()["status"] == "success"
    assert response.json()["data"]["schema_version"] == "0.2-provisional"


def test_captured_evidence_keeps_original_provenance(client):
    response = client.get("/api/demo/captured-climate")
    assert response.status_code == 200
    assert response.json() == json.loads(
        (ROOT / "server/examples/nasa_power_real.json").read_text()
    )


def test_unknown_interface_and_oversized_request(client):
    assert client.post("/api/engine/unknown", json={}).status_code == 404
    assert client.post("/api/engine/integration", content=b"x" * 2_000_001).status_code == 413
    assert client.post("/api/engine/integration", content=b"not JSON").status_code == 422
    assert client.post("/api/engine/integration", json=[]).status_code == 422


def test_timeout_kills_process_and_uses_fixed_executable(client, monkeypatch):
    process = AsyncMock()
    process.returncode = None
    process.kill = lambda: None
    launch = AsyncMock(return_value=process)

    async def timeout(coroutine, seconds):
        coroutine.close()
        assert seconds == 20
        raise asyncio.TimeoutError

    monkeypatch.setattr(web_demo.asyncio, "create_subprocess_exec", launch)
    monkeypatch.setattr(web_demo.asyncio, "wait_for", timeout)
    assert client.post("/api/engine/integration", json={}).status_code == 504
    assert launch.call_args.args == (str(ENGINE),)
    assert "shell" not in launch.call_args.kwargs
    process.wait.assert_awaited_once()


def test_missing_engine_is_explicitly_unavailable(tmp_path):
    with TestClient(create_demo_app(engine=tmp_path / "missing.exe")) as client:
        assert client.post("/api/engine/integration", json={}).status_code == 503
