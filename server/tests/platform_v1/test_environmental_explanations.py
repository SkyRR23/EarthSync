"""Cached real 7G snapshots; these are not new live observations."""

import json
import time
from datetime import datetime, timedelta
from pathlib import Path
from uuid import uuid4

from earthsync.platform_v1.environmental_explanations import assistant_references
from earthsync.platform_v1.journal import Journal, JournalInput
from earthsync.platform_v1.store import encoded

ROOT = Path(__file__).parents[3]


def saved_job(store, farm_id, kind, filename):
    raw = json.loads(
        (ROOT / "docs/integration/7g/evidence/browser" / filename).read_text()
    )
    ident = str(uuid4())
    with store.connection() as db:
        db.execute(
            "INSERT INTO jobs VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (
                ident,
                "alice",
                ident,
                kind,
                "succeeded",
                encoded({"farm_id": str(farm_id)}),
                encoded(raw["result"]),
                None,
                0,
                time.time(),
                time.time(),
            ),
        )
    return ident, raw["result"]


def test_cached_real_source_explanations_and_expiry_preserve_scientific_gates(
    store, farm_input
):
    farm = store.create_farm("alice", farm_input)
    soil_id, soil = saved_job(store, farm.id, "soil_map", "soil-map-job.json")
    _, forecast = saved_job(store, farm.id, "forecast", "forecast-job.json")
    now = datetime.fromisoformat(forecast["retrieved_at"])
    sources, evidence = assistant_references(store, "alice", farm.id, now)
    assert len(sources) == len(evidence) == 2
    ph = next(e for e in evidence if e["metric"] == "soil_reference_summary")
    assert (
        "250 m" in ph["value"] and "pH" in ph["value"] and ph["quality"] == "unverified"
    )
    assert ph["retrieved_at"] == soil["retrieved_at"]
    assert all(s["url"].startswith("https://") for s in sources)
    _, stale = assistant_references(store, "alice", farm.id, now + timedelta(days=2))
    assert (
        next(e for e in stale if e["metric"] == "forecast_reference_summary")["quality"]
        == "stale"
    )
    saved = Journal(store).save(
        "alice",
        farm.id,
        JournalInput(
            id=uuid4(),
            kind="warning_acknowledgment",
            occurred_on="2024-01-01",
            environmental_job_ids=[soil_id],
        ),
    )
    assert saved["environmental_job_ids"] == [soil_id]
    assert saved["data_type"] == "farmer_reported"
