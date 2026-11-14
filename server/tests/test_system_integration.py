"""7H: main launcher app -> mounted services -> actual compiled Rust.

Provider-shaped fixtures are explicitly synthetic. Live provider verification is
separate and opt-in; these tests never claim field/scientific validation.
"""

import copy
import io
import json

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from earthsync.catalog_adapter import catalog_view, profile_mapping
from earthsync.evidence.store import PhotoStore
from earthsync.web_demo import ROOT, create_demo_app

TOKEN = "private-integration-test-token-123456789"
AUTH = {"Authorization": f"Bearer {TOKEN}"}
FARM = {
    "field_id": "farmer-confirmed-demo",
    "point": {"latitude": 42, "longitude": -93},
    "confirmed_on": "2026-11-14",
}


@pytest.fixture
def client(tmp_path):
    static = tmp_path / "web"
    static.mkdir()
    (static / "index.html").write_text("<html>Flutter test host</html>")
    with TestClient(
        create_demo_app(
            static_dir=static,
            evidence_store=PhotoStore(tmp_path / "private"),
            evidence_token=TOKEN,
        ),
        client=("127.0.0.1", 50000),
    ) as client:
        yield client


def image(color):
    output = io.BytesIO()
    Image.new("RGB", (8, 8), color).save(output, format="PNG")
    return output.getvalue()


def test_launcher_mounts_services_before_static_host(client):
    assert "Flutter test host" in client.get("/").text
    assert client.get("/api/v1/health").json()["upstream_checked"] is False
    assert (
        client.get("/api/demo/capabilities").json()["identity"]
        == "no_production_accounts"
    )
    assert client.get("/api/environmental/v1/health").status_code == 200
    assert (
        client.get("/api/catalog/v1/profiles").json()["reference"][
            "recommendation_eligible"
        ]
        is False
    )
    for path in ["/api/not-a-route", "/api/assistant/v1/missing"]:
        response = client.get(path)
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "UNKNOWN_API"
        assert "text/html" not in response.headers["content-type"]


def test_environmental_and_satellite_missing_are_null_not_healthy(client):
    response = client.post(
        "/api/environmental/v1/context",
        json={
            "schema_version": "environmental-context/1.0-proposal",
            "target": {
                "kind": "confirmed_farm",
                "field_id": FARM["field_id"],
                "farmer_confirmed": True,
                "point": FARM["point"],
            },
        },
    )
    assert response.status_code == 200
    result = response.json()
    assert result["situation"]["agricultural_diagnosis"] is None
    assert result["situation"]["crop_recommendations"] is None
    assert all(
        e["availability"] == "unavailable" and e["values"] == []
        for e in result["evidence"]
    )
    timeline = client.post(
        "/api/satellite/v1/timeline",
        json={
            "field": {
                "farm_id": FARM["field_id"],
                "confirmed_by_farmer": True,
                "point": FARM["point"],
            },
            "start": "2026-01-01",
            "end": "2026-02-01",
        },
    ).json()
    assert timeline["events"] == []
    assert len(timeline["providers"]) == 2
    assert all(p["status"] == "unavailable" for p in timeline["providers"])


def test_private_photo_crud_and_auth_under_normal_launcher(client):
    prefix = "/api/evidence/v1/photos"
    metadata = {
        "source": "browser_file",
        "category": "crop",
        "data_kind": "synthetic",
        "farm": {"farm_id": FARM["field_id"], "confirmed_by_farmer": True},
    }
    headers = {
        **AUTH,
        "Content-Type": "image/png",
        "X-EarthSync-Metadata": json.dumps(metadata),
    }
    assert client.get(prefix).status_code == 401
    uploaded = client.post(prefix, headers=headers, content=image("green"))
    assert uploaded.status_code == 201
    photo = uploaded.json()
    url = f"{prefix}/{photo['id']}"
    assert photo["position"] is None and photo["metadata_stripped"] is True
    for changed in [
        "Bearer another-private-user-token-123456789",
        "Bearer " + FARM["field_id"],
        "",
    ]:
        for method in ["GET", "PUT", "DELETE"]:
            assert (
                client.request(
                    method, url, headers={"Authorization": changed}
                ).status_code
                == 401
            )
    # Changing a farm identifier in a query cannot bypass the bearer boundary.
    assert client.get(prefix, params={"farm_id": FARM["field_id"]}).status_code == 401
    retrieved = client.get(url + "/image", headers=AUTH)
    assert (
        retrieved.status_code == 200
        and retrieved.headers["cache-control"] == "no-store"
    )
    assert not Image.open(io.BytesIO(retrieved.content)).info
    changed = client.put(url, headers=headers, content=image("blue")).json()
    assert changed["id"] == photo["id"] and changed["sha256"] != photo["sha256"]
    assert client.delete(url, headers=AUTH).status_code == 204
    assert client.get(url, headers=AUTH).status_code == 404


def test_mounted_photo_workspace_rejects_plain_http_remote_clients(tmp_path):
    app = create_demo_app(
        evidence_store=PhotoStore(tmp_path / "private"), evidence_token=TOKEN
    )
    with TestClient(app, client=("192.168.1.2", 50000)) as client:
        assert client.get("/api/evidence/v1/photos", headers=AUTH).status_code == 403
        assert client.get("/api/v1/health").status_code == 200
    with TestClient(
        app, base_url="https://localhost", client=("192.168.1.2", 50000)
    ) as client:
        assert client.get("/api/evidence/v1/photos", headers=AUTH).status_code == 200


def test_unconfigured_photos_fail_closed_without_breaking_other_services(
    tmp_path, monkeypatch
):
    monkeypatch.delenv("EARTHSYNC_EVIDENCE_TOKEN", raising=False)
    with TestClient(create_demo_app(static_dir=tmp_path)) as client:
        assert (
            client.get("/api/demo/capabilities").json()["photo_workspace"] == "disabled"
        )
        assert client.get("/api/evidence/v1/photos").status_code == 404
        assert client.get("/api/v1/health").status_code == 200


def test_real_compiled_v03_synthetic_and_validation_path(client):
    request = client.get("/api/demo/synthetic-v03").json()
    assert request["mode"] == "software_test"
    result = client.post("/api/engine/v03", json=request).json()
    assert result["status"] == "success"
    data = result["data"]
    assert data["schema_version"] == "earthsync.engine.v0.3.0"
    assert data["software_test_only"] is True
    assert data["context"] == request
    assert any(
        f["status"] == "supported_by_supplied_evidence" for f in data["findings"]
    )
    assert all(s["status"] == "insufficient_information" for s in data["summaries"])
    request["farm"]["point"]["latitude"] = 100
    rejected = client.post("/api/engine/v03", json=request).json()
    assert rejected["error"]["status"] == "input_or_source_validation_failure"
    assert rejected["schema_version"] == "earthsync.engine.v0.3.0"


def test_catalog_mapping_is_explicit_reference_only_and_rust_compatible(client):
    view = catalog_view()
    assert len(view["reference"]["profiles"]) == 8
    assert sum(m["engine_profile"] is not None for m in view["mappings"]) == 6
    for profile in view["reference"]["profiles"]:
        query = {
            "profile_id": profile["id"],
            "farm": FARM,
            "start": "2025-04-15",
            "end": "2025-10-01",
        }
        adapted = client.post("/api/catalog/v1/assessment-request", json=query)
        mapping, blocker = profile_mapping(profile)
        if blocker:
            assert adapted.status_code == 422
            assert adapted.json()["error"]["code"] == "CATALOG_MAPPING_UNAVAILABLE"
            continue
        assert adapted.status_code == 200
        response = adapted.json()
        assert (
            response["reference"] == profile
        )  # Per-parameter citations, units, nulls retained.
        request = response["request"]
        assert request["catalog"] == [mapping]
        assert mapping["rules"] == [] and mapping["review"] == "reference_only"
        assert mapping["approved_for_candidates"] is False
        result = client.post("/api/engine/v03", json=request).json()["data"]
        assert result["software_test_only"] is False
        assert result["candidates"] == []
        assert result["summaries"][0]["status"] == "insufficient_information"
        assert result["findings"][0]["rule_id"] == "catalog.rules"
    promoted = copy.deepcopy(view["reference"]["profiles"][0])
    promoted["recommendation_eligible"] = True
    with pytest.raises(ValueError, match="reference-only"):
        profile_mapping(promoted)


def test_assistant_main_app_no_farm_and_real_rust_statuses(client):
    request = json.loads((ROOT / "docs/assistant/request.v1.json").read_text())
    assert client.post("/api/assistant/v1/chat", json=request).status_code == 200
    synthetic = client.get("/api/demo/synthetic-v03").json()
    actual = client.post("/api/engine/v03", json=synthetic).json()["data"]
    request["question"] = "Explain the crop findings"
    request["expanded"] = True
    request["context"]["decisions"] = [
        {
            "id": f"rust-{i}",
            "scenario_id": s["scenario_id"],
            "status": s["status"],
            "synthetic": True,
        }
        for i, s in enumerate(actual["summaries"])
    ]
    response = client.post("/api/assistant/v1/chat", json=request)
    assert response.status_code == 200
    assert response.json()["decisions"] == [
        {**d, "source_ids": [], "evidence_ids": [], "limitations": []}
        for d in request["context"]["decisions"]
    ]
    for status in ["evidence_not_applicable", "input_or_source_validation_failure"]:
        request["context"]["decisions"][0]["status"] = status
        assert (
            client.post("/api/assistant/v1/chat", json=request).json()["decisions"][0][
                "status"
            ]
            == status
        )


def test_assistant_stream_cap_and_machine_readable_safe_errors(client):
    response = client.post("/api/assistant/v1/chat", content=b"x" * 2_000_001)
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "REQUEST_TOO_LARGE"
    response = client.post(
        "/api/assistant/v1/chat", json={"secret": "private-data-must-not-echo"}
    )
    assert (
        response.status_code == 422
        and "private-data-must-not-echo" not in response.text
    )


async def test_json_api_cap_is_enforced_across_multiple_asgi_chunks(tmp_path):
    import httpx

    async def chunks():
        for _ in range(5):
            yield b"x" * 500_000

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=create_demo_app(static_dir=tmp_path)),
        base_url="http://localhost",
    ) as client:
        response = await client.post("/api/assistant/v1/chat", content=chunks())
        assert response.status_code == 413
        assert response.json()["error"]["code"] == "REQUEST_TOO_LARGE"
        assert response.headers["cache-control"] == "no-store"
