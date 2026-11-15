"""Saved exploration groups. Baselines are explicit farmer declarations, not advice."""

import json
import time
from datetime import datetime, timezone
from uuid import UUID
from typing import Literal

from pydantic import Field, model_validator

from .errors import PlatformError
from .models import Contract
from .store import encoded

Priority = Literal[
    "food",
    "income",
    "less_water",
    "soil",
    "lower_risk",
    "less_labor",
    "nitrogen_potential",
    "erosion",
    "forage",
    "equipment",
    "market",
]


class ComparisonInput(Contract):
    schema_version: Literal["earthsync.comparison.v1"] = "earthsync.comparison.v1"
    id: UUID
    name: str = Field(min_length=1, max_length=150)
    baseline_decision_id: UUID
    alternative_decision_ids: list[UUID] = Field(min_length=2, max_length=5)
    chosen_decision_id: UUID | None = None
    baseline_declared_existing_plan: Literal[True]
    priorities: list[Priority] = Field(default_factory=list, max_length=11)
    practical_constraints: str = Field(default="", max_length=1000)
    exploration_reason: str = Field(min_length=1, max_length=1000)

    @model_validator(mode="after")
    def distinct(self):
        ids = [self.baseline_decision_id, *self.alternative_decision_ids]
        if self.chosen_decision_id and self.chosen_decision_id not in ids:
            raise ValueError("Farmer choice must be one of the strategies")
        if len(set(ids)) != len(ids) or len(set(self.priorities)) != len(
            self.priorities
        ):
            raise ValueError("Strategies and priorities must be distinct")
        return self


class Comparisons:
    def __init__(self, store):
        self.store = store

    def list(self, owner, farm_id):
        with self.store.connection() as db:
            self.store.farm(owner, farm_id, db)
            return [
                json.loads(r[0])
                for r in db.execute(
                    "SELECT document FROM rotation_comparisons WHERE farm_id=? AND owner=? ORDER BY created DESC LIMIT 100",
                    (str(farm_id), owner),
                )
            ]

    def save(self, owner, farm_id, value: ComparisonInput):
        raw = value.model_dump(mode="json")
        with self.store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.store.farm(owner, farm_id, db)
            old = db.execute(
                "SELECT farm_id,document FROM rotation_comparisons WHERE id=? AND owner=?",
                (str(value.id), owner),
            ).fetchone()
            if old:
                saved = json.loads(old[1])
                if old[0] != str(farm_id) or any(saved[k] != v for k, v in raw.items()):
                    raise PlatformError("COMPARISON_ID_CONFLICT", 409)
                return saved
            for ident in [value.baseline_decision_id, *value.alternative_decision_ids]:
                row = db.execute(
                    "SELECT document FROM decisions WHERE id=? AND farm_id=? AND owner=?",
                    (str(ident), str(farm_id), owner),
                ).fetchone()
                if row is None:
                    raise PlatformError("DECISION_NOT_OWNED_BY_FARM", 404)
                result = json.loads(row[0]).get("result", {})
                if (
                    result.get("status") != "success"
                    or result.get("data", {}).get("software_test_only") is not False
                ):
                    raise PlatformError("REAL_SAVED_ASSESSMENT_REQUIRED", 422)
                scenarios = (
                    result.get("data", {}).get("context", {}).get("scenarios", [])
                )
                if len(scenarios) != 1 or len(scenarios[0].get("plans", [])) < 2:
                    raise PlatformError("SAVED_ROTATION_SEQUENCE_REQUIRED", 422)
            if (
                db.execute("SELECT COUNT(*) FROM rotation_comparisons").fetchone()[0]
                >= self.store.max_rows
            ):
                raise PlatformError("STORAGE_QUOTA", 507)
            saved = {
                **raw,
                "farm_id": str(farm_id),
                "data_type": "farmer_reported",
                "recorded_at": datetime.now(timezone.utc).isoformat(),
                "recommendation_eligible": False,
            }
            db.execute(
                "INSERT INTO rotation_comparisons VALUES (?,?,?,?,?)",
                (str(value.id), str(farm_id), owner, encoded(saved), time.time()),
            )
            self.store._audit(
                db,
                owner,
                str(value.id),
                "comparison.existing_plan_explicitly_declared",
                "earthsync.comparison.v1",
            )
            return saved
