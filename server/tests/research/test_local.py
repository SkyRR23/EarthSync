"""Actual existing local boundary, additive migration, photos, reports and recovery."""

from uuid import uuid4

from fastapi.testclient import TestClient

from earthsync.platform_v1.api import PREFIX, create_app
from earthsync.platform_v1.maintenance import backup, restore
from earthsync.platform_v1.store import Store
from earthsync.research.soil import LocalOCR, parse_lab_text
from earthsync.research.vision import VisionExtraction


class MockImageProvider:
    name, model, external, supports_images = "mock", "synthetic", True, True

    def __init__(self):
        self.calls = 0

    def extract(self, pixels, schema):
        self.calls += 1
        if schema is VisionExtraction:
            return {
                "image_type": "crop",
                "observations": [{"feature": "yellowing", "visibility": "visible"}],
                "inconclusive": False,
                "limitations": [],
            }
        return {"transcription": "Sample ID: SYNTHETIC\npH: 6.8"}


class Offline:
    async def get(self, *args):
        raise AssertionError("This workflow must not fetch environmental providers")


def test_local_multimodal_consent_no_automatic_history_and_assisted_restore(
    tmp_path, png, monkeypatch
):
    monkeypatch.setattr(
        LocalOCR,
        "extract",
        lambda self, image: parse_lab_text("Sample ID: SYNTHETIC\npH: 6.4"),
    )
    store, provider = Store(tmp_path / "local"), MockImageProvider()
    app = create_app(
        store=store, transport=Offline(), local_enabled=True, vision=provider
    )
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 12345)
    ) as client:
        farm = client.post(
            PREFIX + "/farms",
            json={
                "name": "Synthetic only",
                "confirmed_point": {"latitude": 42.03, "longitude": -93.62},
                "confirmed_on": "2026-11-15",
                "production_system": "rainfed",
            },
        ).json()
        route = PREFIX + f"/farms/{farm['id']}"
        photo = client.post(
            route + "/photos", content=png, headers={"content-type": "image/png"}
        ).json()
        analyze = route + f"/photos/{photo['id']}/analyze"
        assert client.get(PREFIX + "/image-capabilities").json()["model"] == "synthetic"
        assert client.post(analyze, json={"image_kind": "crop"}).status_code == 422
        assert provider.calls == 0
        result = client.post(
            analyze,
            json={
                "image_kind": "crop",
                "crop": "maize",
                "external_image_consent": True,
            },
        ).json()
        assert result["citations"] and result["human_confirmed"] is False
        assert result["saved_environmental_evidence"]["station_measurements"] == []
        assert client.get(route + "/observations").json() == []
        assert (
            client.post(
                PREFIX + f"/farms/{uuid4()}/photos/{photo['id']}/analyze",
                json={"image_kind": "crop", "external_image_consent": True},
            ).status_code
            == 404
        )
        assert provider.calls == 1
        report = client.post(
            route + f"/photos/{photo['id']}/lab-extraction",
            json={"request_ai_assistance": True, "external_image_consent": True},
        ).json()
        assert report["confirmed"] is None
        assert report["original"]["values"][0]["value"] == 6.4
        assert report["original"]["ai_assistance"]["values"][0]["value"] == 6.8
        value = {
            "confirmed": True,
            "document_kind": "laboratory_report",
            "sample_id": "SYNTHETIC",
            "values": [
                {**report["original"]["ai_assistance"]["values"][0], "value": 6.6}
            ],
        }
        assert (
            client.post(
                route + f"/lab-reports/{report['id']}/confirm", json=value
            ).status_code
            == 200
        )
    backup(store, tmp_path / "backup")
    restored = restore(tmp_path / "backup", tmp_path / "restored")
    with restored.connection() as db:
        import json

        row = db.execute("SELECT original,confirmed FROM crop_lab_reports").fetchone()
        assert json.loads(row["original"])["values"][0]["value"] == 6.4
        assert json.loads(row["original"])["ai_assistance"]["values"][0]["value"] == 6.8
        assert json.loads(row["confirmed"])["values"][0]["value"] == 6.6


def test_local_farmer_workflow_and_recovery(tmp_path, png, monkeypatch):
    monkeypatch.setattr(
        LocalOCR,
        "extract",
        lambda self, data: parse_lab_text(
            "Laboratory: Synthetic test\nSample ID: TEST\nDepth: 0-5 cm\nMethod: pH in water\npH: 6.4"
        ),
    )
    store = Store(tmp_path / "local")
    app = create_app(store=store, transport=Offline(), local_enabled=True)
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 12345)
    ) as client:
        farm = client.post(
            PREFIX + "/farms",
            json={
                "name": "Synthetic test, no ground truth",
                "confirmed_point": {"latitude": 42.03, "longitude": -93.62},
                "confirmed_on": "2026-11-15",
                "production_system": "rainfed",
            },
        ).json()
        route = PREFIX + f"/farms/{farm['id']}"
        photo = client.post(
            route + "/photos", content=png, headers={"content-type": "image/png"}
        ).json()
        assert (
            client.post(route + f"/photos/{photo['id']}/analyze").json()["status"]
            == "unavailable"
        )
        report = client.post(route + f"/photos/{photo['id']}/lab-extraction").json()
        assert report["confirmed"] is None
        confirmed = client.post(
            route + f"/lab-reports/{report['id']}/confirm",
            json={
                "confirmed": True,
                "document_kind": "laboratory_report",
                "sample_id": "TEST",
                "values": [{**report["original"]["values"][0], "value": 6.7}],
            },
        ).json()
        assert confirmed["original"]["values"][0]["value"] == 6.4
        assert confirmed["confirmed"]["values"][0]["value"] == 6.7
        context = client.get(route + "/soil-context").json()
        assert context["modeled_regional_reference"] == []
        assert len(context["laboratory_sample_transcriptions"]) == 1
        assert context["recommendation_eligible"] is False
        assert (
            client.post(
                PREFIX + f"/farms/{uuid4()}/photos/{photo['id']}/lab-extraction"
            ).status_code
            == 404
        )
        assert client.post(
            PREFIX + "/crop-intelligence", json={"crop": "rice", "question": "soil pH"}
        ).json()["citations"]
    backup(store, tmp_path / "backup")
    restored = restore(tmp_path / "backup", tmp_path / "restored")
    with restored.connection() as db:
        row = db.execute("SELECT * FROM crop_lab_reports").fetchone()
        assert row["id"] == report["id"]
        assert "6.7" in row["confirmed"]
    app = create_app(store=restored, transport=Offline(), local_enabled=True)
    with TestClient(
        app, base_url="http://127.0.0.1", client=("127.0.0.1", 12345)
    ) as client:
        assert (
            client.get(route + "/lab-reports").json()[0]["confirmed"]["sample_id"]
            == "TEST"
        )
        assert client.delete(route + f"/photos/{photo['id']}").status_code == 204
        assert client.get(route + "/lab-reports").json() == []
