"""Farmer reports, distinct from measurements and explicit Rust history projection."""

import json
import time
from datetime import date, datetime, timezone
from typing import Literal
from uuid import UUID, uuid4

from pydantic import Field, model_validator

from .comparisons import Priority
from .errors import PlatformError
from .models import Contract, HistoryInput
from .store import encoded


class SoilTest(Contract):
    property: Literal["ph", "organic_carbon", "nitrogen", "clay", "sand", "silt"]
    value: float
    unit: Literal["pH", "g/kg", "%"]
    top_cm: float = Field(ge=0, le=1000)
    bottom_cm: float = Field(gt=0, le=1000)
    source: str = Field(min_length=1, max_length=200)

    @model_validator(mode="after")
    def valid(self):
        if self.bottom_cm <= self.top_cm:
            raise ValueError("Soil depth must be ordered")
        expected = (
            "pH"
            if self.property == "ph"
            else "%"
            if self.property in {"clay", "sand", "silt"}
            else "g/kg"
        )
        if self.unit != expected or self.value < 0:
            raise ValueError("Property needs explicit compatible units")
        if (self.property == "ph" and self.value > 14) or (
            self.unit == "%" and self.value > 100
        ):
            raise ValueError("Soil value outside physical range")
        return self


class JournalInput(Contract):
    schema_version: Literal["earthsync.journal.v1"] = "earthsync.journal.v1"
    id: UUID
    kind: Literal[
        "season",
        "fallow",
        "bare_field",
        "plan",
        "stage",
        "irrigation",
        "management",
        "observation",
        "problem",
        "soil_test",
        "priorities",
        "warning_acknowledgment",
    ]
    occurred_on: date
    crop_id: str | None = Field(
        default=None, pattern=r"^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$", max_length=150
    )
    crop_name: str | None = Field(default=None, max_length=150)
    harvest_on: date | None = None
    stage: Literal[
        "unknown",
        "sowing",
        "emergence",
        "vegetative",
        "flowering",
        "fruiting",
        "maturity",
        "harvested",
    ] = "unknown"
    irrigation: Literal["unknown", "available", "limited", "none"] = "unknown"
    drainage: Literal["unknown", "good", "moderate", "poor"] = "unknown"
    water_access: Literal["unknown", "rain_only", "well", "canal", "pond", "other"] = (
        "unknown"
    )
    priorities: list[Priority] = Field(default_factory=list, max_length=11)
    resources: str | None = Field(default=None, max_length=500)
    notes: str = Field(default="", max_length=2000)
    soil_test: SoilTest | None = None
    photo_ids: list[UUID] = Field(default_factory=list, max_length=10)
    evidence_ids: list[str] = Field(default_factory=list, max_length=20)
    decision_id: UUID | None = None

    @model_validator(mode="after")
    def valid(self):
        if self.kind != "plan" and self.occurred_on > date.today():
            raise ValueError("Actual reports cannot be future events")
        if self.harvest_on and self.harvest_on < self.occurred_on:
            raise ValueError("Harvest must follow planting")
        if self.kind == "season" and self.harvest_on and self.harvest_on > date.today():
            raise ValueError("Actual harvest cannot be in the future; use a plan")
        if self.kind in {"season", "plan"} and not self.crop_name:
            raise ValueError("Crop identity must be reported")
        if (self.kind == "soil_test") != (self.soil_test is not None):
            raise ValueError("Soil tests require source, units, value and depth")
        if (
            len(set(self.priorities)) != len(self.priorities)
            or len(set(self.photo_ids)) != len(self.photo_ids)
            or len(set(self.evidence_ids)) != len(self.evidence_ids)
        ):
            raise ValueError("Duplicate selections")
        if any(len(e) > 100 for e in self.evidence_ids):
            raise ValueError("Invalid evidence ID")
        return self


class Journal:
    def __init__(self, store):
        self.store = store

    def list(self, owner, farm_id):
        with self.store.connection() as db:
            self.store.farm(owner, farm_id, db)
            return [
                json.loads(r[0])
                for r in db.execute(
                    "SELECT document FROM farmer_journal WHERE owner=? AND farm_id=? ORDER BY created DESC LIMIT 200",
                    (owner, str(farm_id)),
                )
            ]

    def save(self, owner, farm_id, value: JournalInput):
        raw = value.model_dump(mode="json")
        with self.store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.store.farm(owner, farm_id, db)
            old = db.execute(
                "SELECT farm_id,document FROM farmer_journal WHERE id=? AND owner=?",
                (str(value.id), owner),
            ).fetchone()
            if old:
                saved = json.loads(old[1])
                if old[0] != str(farm_id) or any(saved[k] != v for k, v in raw.items()):
                    raise PlatformError("JOURNAL_ID_CONFLICT", 409)
                return saved
            for ident in value.photo_ids:
                if not db.execute(
                    "SELECT 1 FROM artifacts WHERE id=? AND farm_id=? AND owner=? AND kind='photo'",
                    (str(ident), str(farm_id), owner),
                ).fetchone():
                    raise PlatformError("PHOTO_NOT_OWNED_BY_FARM", 404)
            for ident in value.evidence_ids:
                if not db.execute(
                    "SELECT 1 FROM farm_evidence WHERE evidence_id=? AND farm_id=? AND owner=?",
                    (ident, str(farm_id), owner),
                ).fetchone():
                    raise PlatformError("EVIDENCE_NOT_OWNED_BY_FARM", 404)
            if (
                value.decision_id
                and not db.execute(
                    "SELECT 1 FROM decisions WHERE id=? AND farm_id=? AND owner=?",
                    (str(value.decision_id), str(farm_id), owner),
                ).fetchone()
            ):
                raise PlatformError("DECISION_NOT_OWNED_BY_FARM", 404)
            if (
                db.execute("SELECT COUNT(*) FROM farmer_journal").fetchone()[0]
                >= self.store.max_rows
            ):
                raise PlatformError("STORAGE_QUOTA", 507)
            result = {
                **raw,
                "farm_id": str(farm_id),
                "data_type": "farmer_reported",
                "recorded_at": datetime.now(timezone.utc).isoformat(),
            }
            db.execute(
                "INSERT INTO farmer_journal VALUES (?,?,?,?,?)",
                (str(value.id), str(farm_id), owner, encoded(result), time.time()),
            )
            self.store._audit(
                db,
                owner,
                str(value.id),
                "journal.explicitly_reported",
                "earthsync.journal.v1",
            )
        return result

    def confirm_history(self, owner, farm_id, entry_id):
        """Explicit, idempotent copy of a completed actual season only."""
        with self.store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.store.farm(owner, farm_id, db)
            row = db.execute(
                "SELECT document FROM farmer_journal WHERE id=? AND owner=? AND farm_id=?",
                (str(entry_id), owner, str(farm_id)),
            ).fetchone()
            if row is None:
                raise PlatformError("NOT_FOUND", 404)
            report = json.loads(row[0])
            if (
                report["kind"] != "season"
                or not report["harvest_on"]
                or not report["crop_id"]
            ):
                raise PlatformError("COMPLETED_CATALOG_SEASON_REQUIRED", 422)
            prior = db.execute(
                "SELECT history_id FROM journal_history_links WHERE entry_id=? AND owner=?",
                (str(entry_id), owner),
            ).fetchone()
            if prior:
                return {"history_id": prior[0], "data_type": "farmer_reported"}
            history = HistoryInput(
                crop_id=report["crop_id"],
                start=report["occurred_on"],
                end=report["harvest_on"],
            )
            ident = str(uuid4())
            value = {
                "id": ident,
                **history.model_dump(mode="json"),
                "reported_at": time.time(),
                "data_type": "farmer_reported",
            }
            self.store._quota(db, "history")
            db.execute(
                "INSERT INTO history VALUES (?,?,?,?,?)",
                (ident, str(farm_id), owner, encoded(value), time.time()),
            )
            db.execute(
                "INSERT INTO journal_history_links VALUES (?,?,?)",
                (str(entry_id), owner, ident),
            )
            self.store._audit(db, owner, ident, "journal.history_explicitly_confirmed")
            return {"history_id": ident, "data_type": "farmer_reported"}
