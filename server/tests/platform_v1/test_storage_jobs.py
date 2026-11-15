import asyncio
import hashlib
from pathlib import Path
import json
import sqlite3

import pytest

from earthsync.platform_v1.errors import PlatformError
from earthsync.platform_v1.jobs import Jobs
from earthsync.platform_v1.store import Store, cache_key


def test_migration_idempotent_and_foreign_keys(store, farm_input, records):
    store.migrate()
    farm = store.create_farm("alice", farm_input)
    store.save_evidence("alice", records[0], farm.id)
    assert store.ready()
    with store.connection() as db:
        expected = {
            int(p.name.split("_")[0]): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (
                Path(__file__).parents[2] / "earthsync/platform_v1/migrations"
            ).glob("*.sql")
            if p.name != "040_crop_lab_reports.sql"
        }
        assert (
            dict(db.execute("SELECT version,sha256 FROM schema_migrations")) == expected
        )
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                "INSERT INTO farm_evidence VALUES (?,?,?)",
                (str(farm.id), "bob", records[0].id),
            )


def test_cross_owner_and_binding(store, farm_input, records):
    farm = store.create_farm("alice", farm_input)
    store.save_evidence("alice", records[0], farm.id)
    for action in [
        lambda: store.farm("bob", farm.id),
        lambda: store.evidence("bob", records[0].id),
        lambda: store.evidence("bob", records[0].id, farm.id),
        lambda: store.save_evidence("bob", records[0], farm.id),
    ]:
        with pytest.raises(PlatformError, match="NOT_FOUND"):
            action()
    assert store.farms("bob") == []
    changed = records[0].model_copy(deep=True)
    changed.measurements[0].value = 100
    with pytest.raises(PlatformError, match="IMMUTABLE_EVIDENCE_CONFLICT"):
        store.save_evidence("alice", changed)


def test_quotas_roll_back(store, farm_input):
    store.max_rows = 1
    store.create_farm("alice", farm_input)
    with pytest.raises(PlatformError, match="STORAGE_QUOTA"):
        store.create_farm("alice", farm_input)
    assert len(store.farms("alice")) == 1


def test_cache_contract_lineage_and_expiry(store):
    a = cache_key("POWER", "daily", "MERRA2.v1", {"longitude": 1, "latitude": 2})
    assert a != cache_key(
        "POWER", "daily", "GEOSIT.v1", {"longitude": 1, "latitude": 2}
    )
    assert a != cache_key(
        "POWER", "daily", "MERRA2.v1", {"longitude": 2, "latitude": 1}
    )
    store.cache_put(a, {"test": 1}, ttl=-1)
    assert store.cache_get(a) is None
    store.cache_put(a, {"test": 2})
    assert store.cache_get(a) == {"test": 2}


def test_backup_restore(store, farm_input, records, tmp_path):
    farm = store.create_farm("owner", farm_input)
    store.save_evidence("owner", records[0], farm.id)
    target = tmp_path / "backup.sqlite3"
    store.backup(target)
    restored_dir = tmp_path / "restored"
    restored_dir.mkdir()
    (restored_dir / "platform.sqlite3").write_bytes(target.read_bytes())
    restored = Store(restored_dir)
    assert restored.ready()
    assert restored.farm("owner", farm.id) == farm
    assert restored.evidence("owner", records[0].id, farm.id) == records[0]
    with pytest.raises(ValueError):
        store.backup(target)


async def test_jobs_dedup_limit_cancel_and_ownership(store):
    gate = asyncio.Event()
    started = asyncio.Event()

    async def handler(owner, request):
        started.set()
        await gate.wait()
        return {"value": 5}

    jobs = Jobs(store, {"test": handler}, capacity=1, workers=1)
    first = await jobs.submit("alice", "test", "same", {})
    assert (await jobs.submit("alice", "test", "same", {}))["id"] == first["id"]
    with pytest.raises(PlatformError, match="JOB_CAPACITY"):
        await jobs.submit("alice", "test", "different", {})
    # Start workers without recovery to exercise a previously accepted queued job.
    jobs.tasks = [asyncio.create_task(jobs._worker())]
    await asyncio.wait_for(started.wait(), 1)
    with pytest.raises(PlatformError, match="NOT_FOUND"):
        jobs.cancel("bob", first["id"])
    assert jobs.cancel("alice", first["id"])["status"] == "cancelled"
    await jobs.close()


async def test_jobs_timeout_restart_and_retryability(store):
    async def slow(owner, request):
        await asyncio.Event().wait()

    jobs = Jobs(store, {"slow": slow}, workers=1, deadline=0.02)
    await jobs.start()
    job = await jobs.submit("alice", "slow", "key", {})
    await asyncio.wait_for(jobs.queue.join(), 1)
    assert jobs.get("alice", job["id"])["error"] == "TIMEOUT"
    assert jobs.get("alice", job["id"])["retryable"]
    await jobs.close()
    queued = await jobs.submit("alice", "slow", "new", {})
    restarted = Jobs(store, {"slow": slow})
    await restarted.start()
    assert restarted.get("alice", queued["id"])["error"] == "WORKER_RESTARTED"
    await restarted.close()


async def test_terminal_job_does_not_expose_exception(store):
    async def broken(owner, request):
        raise RuntimeError("secret private coordinates")

    jobs = Jobs(store, {"test": broken}, workers=1)
    await jobs.start()
    job = await jobs.submit("alice", "test", "key", {})
    await asyncio.wait_for(jobs.queue.join(), 1)
    result = jobs.get("alice", job["id"])
    assert result["error"] == "PROCESSING_FAILURE"
    assert "secret" not in json.dumps(result)
    await jobs.close()
