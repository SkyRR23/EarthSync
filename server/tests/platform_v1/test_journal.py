"""Synthetic farmer reports; no provider or scientific acceptance claims."""

from datetime import date, timedelta
from uuid import uuid4

import pytest
from pydantic import ValidationError

from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.journal import Journal, JournalInput
from earthsync.platform_v1.store import Store


def entry(**changes):
    return JournalInput(
        id=uuid4(),
        kind="season",
        occurred_on="2024-01-01",
        harvest_on="2024-04-01",
        crop_name="Reported rice",
        crop_id="rice@catalog-v1",
        **changes,
    )


def test_explicit_persistence_projection_restart_backup(store, farm_input, tmp_path):
    farm = store.create_farm("alice", farm_input)
    journal = Journal(store)
    value = entry()
    saved = journal.save("alice", farm.id, value)
    assert saved["data_type"] == "farmer_reported"
    assert journal.save("alice", farm.id, value) == saved
    assert store.history("alice", farm.id) == []
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        journal.list("bob", farm.id)
    projected = journal.confirm_history("alice", farm.id, value.id)
    assert journal.confirm_history("alice", farm.id, value.id) == projected
    assert len(store.history("alice", farm.id)) == 1
    restarted = Store(store.path.parent)
    assert Journal(restarted).list("alice", farm.id) == [saved]
    backup_dir = tmp_path / "restore"
    backup_dir.mkdir()
    store.backup(backup_dir / "platform.sqlite3")
    restored = Store(backup_dir)
    assert restored.history("alice", farm.id) == restarted.history("alice", farm.id)
    assert Journal(restored).list("alice", farm.id) == [saved]
    assert restored.ready()


def test_farm_scope_id_conflicts_and_plan_not_promoted(store, farm_input):
    farm = store.create_farm("alice", farm_input)
    other = store.create_farm("alice", farm_input)
    journal = Journal(store)
    value = entry()
    journal.save("alice", farm.id, value)
    with pytest.raises(PlatformError, match="JOURNAL_ID_CONFLICT"):
        journal.save("alice", other.id, value)
    with pytest.raises(PlatformError, match="JOURNAL_ID_CONFLICT"):
        journal.save("alice", farm.id, value.model_copy(update={"notes": "Changed"}))
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        journal.confirm_history("alice", other.id, value.id)
    plan = value.model_copy(update={"id": uuid4(), "kind": "plan"})
    journal.save("alice", farm.id, plan)
    with pytest.raises(PlatformError, match="COMPLETED_CATALOG_SEASON_REQUIRED"):
        journal.confirm_history("alice", farm.id, plan.id)
    assert store.history("alice", farm.id) == []


def test_actual_future_and_invalid_soil_rejected():
    with pytest.raises(ValidationError):
        JournalInput(
            id=uuid4(), kind="observation", occurred_on=date.today() + timedelta(days=1)
        )
    for change in [dict(unit="%"), dict(value=15), dict(bottom_cm=0)]:
        with pytest.raises(ValidationError):
            JournalInput(
                id=uuid4(),
                kind="soil_test",
                occurred_on="2024-01-01",
                soil_test={
                    "property": "ph",
                    "unit": "pH",
                    "value": 6,
                    "top_cm": 0,
                    "bottom_cm": 20,
                    "source": "Farmer supplied lab report",
                    **change,
                },
            )


def test_private_photo_evidence_and_decision_association(store, farm_input):
    farm = store.create_farm("alice", farm_input)
    for changes, error in [
        ({"photo_ids": [uuid4()]}, "PHOTO_NOT_OWNED_BY_FARM"),
        ({"evidence_ids": ["ev_missing"]}, "EVIDENCE_NOT_OWNED_BY_FARM"),
        ({"decision_id": uuid4()}, "DECISION_NOT_OWNED_BY_FARM"),
    ]:
        with pytest.raises(PlatformError, match=error):
            Journal(store).save("alice", farm.id, entry(**changes))
    assert Journal(store).list("alice", farm.id) == []


def test_quota_is_atomic(store, farm_input):
    farm = store.create_farm("alice", farm_input)
    Journal(store).save("alice", farm.id, entry())
    store.max_rows = 1
    with pytest.raises(PlatformError, match="STORAGE_QUOTA"):
        Journal(store).save("alice", farm.id, entry())
    assert len(Journal(store).list("alice", farm.id)) == 1


def test_http_journal_and_grounded_assistant(store, farm_input):
    from test_api_engine import local_client
    from earthsync.platform_v1.api import PREFIX
    from earthsync.platform_v1.context import assistant_context
    from earthsync.assistant.models import ChatRequest
    from earthsync.assistant.service import explain

    with local_client(store) as client:
        farm = client.post(
            PREFIX + "/farms", json=farm_input.model_dump(mode="json")
        ).json()
        path = PREFIX + "/farms/" + farm["id"] + "/journal"
        raw = entry(notes="Unreviewed farmer observation").model_dump(mode="json")
        response = client.post(path, json=raw)
        assert response.status_code == 201
        assert client.post(path, json=raw).json() == response.json()
        assert len(client.get(path).json()) == 1
        assert (
            client.post(path + "/" + raw["id"] + "/confirm-history").status_code == 201
        )
        assert (
            client.get(path, headers={"Origin": "https://attacker.example"}).status_code
            == 403
        )
        assert (
            client.get(PREFIX + "/farms/" + str(uuid4()) + "/journal").status_code
            == 404
        )
        result = client.get(PREFIX + "/crop-options", params={"q": "paddy"})
        assert result.status_code == 200
        assert any("paddy" in c["aliases"] for c in result.json()["crops"])
        assert result.json()["recommendation_eligible"] is False
    context = assistant_context(store, "local-single-user", farm["id"])
    answer = explain(
        ChatRequest(question="What is in my saved farm history?", context=context)
    )
    assert answer.intent == "history"
    assert any(
        "Farmer-reported record dated 2024-01-01" in c.text for c in answer.claims
    )
    assert not any(c.category == "deterministic_calculation" for c in answer.claims)
    report = next(e for e in answer.evidence if e.metric == "journal_report")
    assert report.kind == "farmer_reported" and report.quality == "unverified"
