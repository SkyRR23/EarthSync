"""7N compatibility, identity, restart and complete local database integration."""

import hashlib
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from earthsync.platform_v1.api import PREFIX, create_app
from earthsync.platform_v1.catalog import Catalog
from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.maintenance import backup, restore
from earthsync.platform_v1.models import FarmLinkInput
from earthsync.platform_v1.store import Store
from test_api_engine import local_client, rust_engine
from conftest import captured


def link_input(farm_input, revision="2026-11-14T08:00:00Z"):
    return FarmLinkInput(
        local_profile_id="farm-local-42", revision=revision, farm=farm_input
    )


def test_link_retry_revision_restart_restore_and_isolation(store, farm_input, tmp_path):
    value = link_input(farm_input)
    first = store.link_farm("alice", value)
    assert store.link_farm("alice", value) == first
    restarted = Store(store.path.parent)
    assert restarted.farm_link("alice", value.local_profile_id, value.revision) == first
    assert len(restarted.farms("alice")) == 1
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        restarted.farm_link("bob", value.local_profile_id, value.revision)
    changed = value.model_copy(deep=True)
    changed.farm.confirmed_point.latitude = 1
    with pytest.raises(PlatformError, match="FARM_LINK_CONFLICT"):
        restarted.link_farm("alice", changed)
    assert len(restarted.farms("alice")) == 1
    changed.revision = datetime(2026, 11, 14, 9, tzinfo=timezone.utc)
    new = restarted.link_farm("alice", changed)
    assert new["farm"].id != first["farm"].id
    assert restarted.farm_records("alice", new["farm"].id) == []
    backup(restarted, tmp_path / "backup")
    restored = restore(tmp_path / "backup", tmp_path / "restored")
    assert restored.farm_link("alice", value.local_profile_id, value.revision) == first
    assert restored.ready()


def test_link_transaction_rolls_back_with_audit_quota(store, farm_input):
    store.max_rows = 0
    with pytest.raises(PlatformError, match="STORAGE_QUOTA"):
        store.link_farm("alice", link_input(farm_input))
    assert store.farms("alice") == []


def test_link_http_201_and_explicit_read_only_recovery(store, farm_input):
    value = link_input(farm_input)
    with local_client(store) as client:
        for _ in range(2):
            response = client.post(
                PREFIX + "/farm-links", json=value.model_dump(mode="json")
            )
            assert response.status_code == 201
        result = client.get(
            PREFIX + "/farm-links/" + value.local_profile_id,
            params={"revision": value.revision.isoformat()},
        )
        assert result.status_code == 200
        assert result.json() == response.json()
        assert len(client.get(PREFIX + "/farms").json()) == 1


class CapturedPower:
    """Captured real responses, explicitly offline; never a live provider claim."""

    async def get(self, url, params):
        return captured(params["parameters"])


def test_http_daily_database_rust_assistant_restart_restore(
    store, farm_input, query, tmp_path
):
    engine = rust_engine()
    path = Path(__file__).parents[3] / "data/crop-knowledge/v1/catalog.json"
    catalog = Catalog(path, hashlib.sha256(path.read_bytes()).hexdigest())
    app = create_app(
        store=store,
        engine=engine,
        catalog=catalog,
        transport=CapturedPower(),
        local_enabled=True,
        allowed_origins=("http://127.0.0.1:8091",),
    )
    with TestClient(
        app, base_url="http://127.0.0.1:8021", client=("127.0.0.1", 10000)
    ) as client:
        headers = {"Origin": "http://127.0.0.1:8091"}
        assert client.get(PREFIX + "/ready", headers=headers).status_code == 200
        linked = client.post(
            PREFIX + "/farm-links",
            json=link_input(farm_input).model_dump(mode="json"),
            headers=headers,
        ).json()
        ident = linked["farm"]["id"]
        response = client.post(
            PREFIX + "/climate/jobs",
            json={"farm_id": ident, "query": query.model_dump(mode="json")},
            headers=headers,
        )
        assert response.status_code == 202

        async def wait():
            await app.state.jobs.queue.join()

        client.portal.call(wait)
        job = client.get(
            PREFIX + "/jobs/" + response.json()["id"], headers=headers
        ).json()
        assert job["status"] == "succeeded", job
        assert len(job["result"]["records"]) == 3
        repeated = client.post(
            PREFIX + "/climate/jobs",
            json={"query": query.model_dump(mode="json")},
            headers=headers,
        )
        assert repeated.status_code == 202
        client.portal.call(wait)
        repeated_job = client.get(
            PREFIX + "/jobs/" + repeated.json()["id"], headers=headers
        ).json()
        assert repeated_job["status"] == "succeeded", repeated_job
        assert repeated_job["result"]["cache_hit"] is True
        assert repeated_job["result"]["records"] == job["result"]["records"]
        assessment = client.post(
            PREFIX + "/assessments",
            headers=headers,
            json={
                "farm_id": ident,
                "evidence_ids": [r["id"] for r in job["result"]["records"]],
                "profile_ids": ["us_ia_story_corn_rainfed_v1"],
                "pilot_id": "us_ia_story",
                "start": "2024-02-01",
                "end": "2024-02-29",
            },
        )
        assert assessment.status_code == 200, assessment.text
        assert assessment.json()["recommendation_eligible"] is False
        context = client.get(
            PREFIX + f"/farms/{ident}/assistant-context", headers=headers
        ).json()
        assert len(context["evidence"]) == 3
        from earthsync.assistant.models import Context

        Context.model_validate(context)
        assert context["decisions"][0]["status"] == "insufficient_information"
        assert {s["id"] for s in context["sources"]} >= {
            r["id"] for r in job["result"]["records"]
        }
        assert (
            client.get(
                PREFIX + f"/farms/{ident}/decisions",
                headers={"Origin": "http://evil.example"},
            ).status_code
            == 403
        )
    restart = Store(store.path.parent)
    assert len(restart.decisions("local-single-user", ident)) == 1
    backup(restart, tmp_path / "full-backup")
    restored = restore(tmp_path / "full-backup", tmp_path / "full-restore")
    assert len(restored.farm_records("local-single-user", ident)) == 3
    assert len(restored.decisions("local-single-user", ident)) == 1


async def test_actual_rust_validation_details_retained():
    engine = rust_engine()
    with pytest.raises(PlatformError) as caught:
        await engine.analyze({"schema_version": "invalid"})
    assert caught.value.code == "SCIENTIFIC_QUALITY_REJECTION"
    envelope = caught.value.validation
    assert envelope["error"]["status"] == "input_or_source_validation_failure"
    assert isinstance(envelope["error"]["path"], str)
    assert isinstance(envelope["error"]["message"], str)


def test_evidence_key_order_is_not_mutation(store, farm_input, records):
    import json

    farm = store.create_farm("alice", farm_input)
    # Preserve compatibility with documents written before canonical encoding.
    record = records[0]
    store.save_evidence("alice", record, farm.id)
    with store.connection() as db:
        db.execute(
            "UPDATE evidence SET document=? WHERE id=? AND owner=?",
            (record.model_dump_json(), record.id, "alice"),
        )
    from earthsync.platform_v1.models import Evidence

    reordered = Evidence.model_validate(
        json.loads(json.dumps(record.model_dump(mode="json"), sort_keys=True))
    )
    store.save_evidence("alice", reordered, farm.id)
    assert len(store.farm_records("alice", farm.id)) == 1
    changed = record.model_copy(deep=True)
    changed.source_metadata["tampering"] = True
    with pytest.raises(PlatformError, match="IMMUTABLE_EVIDENCE_CONFLICT"):
        store.save_evidence("alice", changed, farm.id)
