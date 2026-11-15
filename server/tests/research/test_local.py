"""Actual existing local boundary, additive migration, photos, reports and recovery."""

from uuid import uuid4

from fastapi.testclient import TestClient

from earthsync.platform_v1.api import PREFIX, create_app
from earthsync.platform_v1.maintenance import backup, restore
from earthsync.platform_v1.store import Store
from earthsync.research.soil import LocalOCR, parse_lab_text


class Offline:
    async def get(self, *args):
        raise AssertionError("This workflow must not fetch environmental providers")


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
