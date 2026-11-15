"""Pinned historical archives and deterministic what-if mechanics, never prediction.

All environmental values are owned Evidence; only accepted WaterPipeline/Rust
calculates ET0. These tables store manifests/results, not a second farm journal.
"""

import hashlib
import json
import time
from datetime import date, datetime, timedelta, timezone
from typing import Literal
from uuid import UUID, uuid4

from pydantic import AwareDatetime, Field, model_validator

from .comparisons import Priority
from .errors import PlatformError
from .farmer_timeline import calendar_intervals
from .models import AssessmentInput, ClimateQuery, Contract, Evidence, PlanSelection
from .providers.power_daily import ENDPOINT, read_daily
from .store import cache_key, encoded
from .water import PARAMS, WaterPipeline, water_dependencies

VERSION = "earthsync.historical.v1"
# Separate extension: daily mean T2M is never substituted by (Tmin+Tmax)/2.
MEAN_CONTRACT = {
    "policy": "power-daily-mean-merra2.v1",
    "parameters": {"T2M": ("temperature", "C", "celsius")},
    "sources": {"T2M": ["MERRA2"]},
}
VARIABLES = {
    "rainfall": ("mm", "sum"),
    "temperature": ("celsius", "mean_valid_days_equal_weight"),
    "tmin": ("celsius", "minimum"),
    "tmax": ("celsius", "maximum"),
    "et0": ("mm", "sum"),
}


def digest(value):
    return hashlib.sha256(encoded(value).encode()).hexdigest()


class Period(Contract):
    start: date
    end: date

    @model_validator(mode="after")
    def ordered(self):
        if self.start.year < 2001 or not 0 <= (self.end - self.start).days < 366:
            raise ValueError("Require 1..366 historical days from 2001")
        if self.end >= date.today():
            raise ValueError("Historical data cannot include today or future days")
        return self


class ArchiveInput(Period):
    farm_id: UUID
    revision: AwareDatetime
    refresh: bool = False


class Assumptions(Contract):
    irrigation: Literal["unknown", "none", "rain_only", "supplemental", "regular"] = (
        "unknown"
    )
    drainage: Literal["unknown", "free", "poor", "standing_water"] = "unknown"
    water_management: str = Field(default="", max_length=1000)
    labor: str = Field(default="", max_length=500)
    equipment: str = Field(default="", max_length=500)
    resources: str = Field(default="", max_length=500)


class DeclaredInterval(Contract):
    kind: Literal["fallow", "bare_field"]
    start: date
    end: date

    @model_validator(mode="after")
    def ordered(self):
        if self.start > self.end:
            raise ValueError("Reversed interval")
        return self


class Strategy(Contract):
    identity: Literal["baseline", "alternative_a", "alternative_b"]
    plans: list[PlanSelection] = Field(min_length=1, max_length=6)
    assumptions: Assumptions = Field(default_factory=Assumptions)
    intervals: list[DeclaredInterval] = Field(default_factory=list, max_length=12)


class SimulationInput(Contract):
    schema_version: Literal["earthsync.simulation.v1"] = "earthsync.simulation.v1"
    id: UUID
    farm_id: UUID
    revision: AwareDatetime
    name: str = Field(min_length=1, max_length=150)
    parent_id: UUID | None = None
    comparison_id: UUID | None = None
    replay_day: date | None = None
    replay_step: Literal["day", "week", "month"] = "day"
    replay_speed: Literal[0.5, 1.0, 2.0, 4.0] = 1.0
    mode: Literal["retrospective", "as_of_date"] = "retrospective"
    decision_at: AwareDatetime | None = None
    archive_ids: list[UUID] = Field(default_factory=list, max_length=22)
    periods: list[Period] = Field(min_length=1, max_length=11)
    strategies: list[Strategy] = Field(min_length=3, max_length=3)
    priorities: list[Priority] = Field(default_factory=list, max_length=11)

    @model_validator(mode="after")
    def valid(self):
        if {s.identity for s in self.strategies} != {
            "baseline",
            "alternative_a",
            "alternative_b",
        }:
            raise ValueError("Require distinct baseline and A/B")
        if (self.mode == "as_of_date") != (self.decision_at is not None):
            raise ValueError("As-of mode requires a decision timestamp only")
        if self.decision_at and self.decision_at > datetime.now(timezone.utc):
            raise ValueError("Historical decision timestamp required")
        if len(set(self.archive_ids)) != len(self.archive_ids) or len(
            set(self.priorities)
        ) != len(self.priorities):
            raise ValueError("Duplicate inputs")
        if len({(p.start, p.end) for p in self.periods}) != len(self.periods):
            raise ValueError("Duplicate periods")
        anchor = self.periods[0]
        if self.replay_day and not anchor.start <= self.replay_day <= anchor.end:
            raise ValueError("Replay day must fit the first simulation period")
        for s in self.strategies:
            if any(
                p.start < anchor.start or p.end > anchor.end
                for p in [*s.plans, *s.intervals]
            ):
                raise ValueError("All hypothetical intervals must fit the first period")
        return self


def summary(records, start, end, *, as_of=None):
    """An accepted-day subtotal is distinct from a complete period total."""
    if as_of is not None:
        as_of = as_of.astimezone(timezone.utc)
    count = (end - start).days + 1
    days = {str(start + timedelta(days=i)): {} for i in range(count)}
    exclusions = []
    for record in records:
        r = record if isinstance(record, Evidence) else Evidence.model_validate(record)
        if (
            not r.usable_for_assessment
            or r.review != "reviewed"
            or r.data_type != "modeled"
        ):
            continue
        if as_of is not None:
            # A present-day archive with unknown historic publication time is
            # never backdated. Retrieval before the cutoff is conservative proof.
            if r.temporal.retrieved_at > as_of:
                exclusions.append(
                    {
                        "evidence_id": r.id,
                        "reason": "AVAILABILITY_BY_DECISION_DATE_NOT_PROVEN",
                    }
                )
                continue
            if r.temporal.issued_at and r.temporal.issued_at > as_of:
                continue
        for m in r.measurements:
            key = str(m.date)
            if key not in days or m.variable not in VARIABLES:
                continue
            if as_of and m.date >= as_of.date():
                continue  # daily record not complete at start of a decision day
            if m.variable in days[key]:
                raise PlatformError("AMBIGUOUS_EVIDENCE", 422)
            days[key][m.variable] = m.value if m.quality == "usable" else None
    metrics = {}
    for variable, (unit, method) in VARIABLES.items():
        values = [d[variable] for d in days.values() if d.get(variable) is not None]
        value = None
        if values:
            value = (
                sum(values)
                if method == "sum"
                else sum(values) / len(values)
                if method.startswith("mean")
                else min(values)
                if method == "minimum"
                else max(values)
            )
        metrics[variable] = {
            "value": value,
            "complete_value": value if len(values) == count else None,
            "valid_days": len(values),
            "missing_days": count - len(values),
            "expected_days": count,
            "unit": unit,
            "method": method,
            "status": "complete"
            if len(values) == count
            else "partial"
            if values
            else "unavailable",
        }
    return {
        "start": str(start),
        "end": str(end),
        "day_basis": "NASA_POWER_LST",
        "metrics": metrics,
        "excluded_evidence": exclusions,
    }


def monthly(records, start, end, **kwargs):
    result = []
    cursor = start
    while cursor <= end:
        next_month = (cursor.replace(day=28) + timedelta(days=4)).replace(day=1)
        result.append(
            summary(records, cursor, min(end, next_month - timedelta(days=1)), **kwargs)
        )
        cursor = next_month
    return result


def contextual_baseline(periods):
    """Equal weight per complete season; partial seasons are excluded, explicit."""
    result = {}
    for variable in VARIABLES:
        usable = [
            (p["start"], p["metrics"][variable]["complete_value"])
            for p in periods
            if p["metrics"][variable]["complete_value"] is not None
        ]
        result[variable] = {
            "value": sum(v for _, v in usable) / len(usable) if usable else None,
            "sample_count": len(usable),
            "periods_used": [p for p, _ in usable],
            "excluded_periods": [
                p["start"]
                for p in periods
                if p["metrics"][variable]["complete_value"] is None
            ],
            "method": "Arithmetic mean of complete season statistics; equal weight per season, no imputation",
            "anomaly_eligible": False,
        }
    return result


class Historical:
    def __init__(self, store, transport, engine, orchestrator):
        self.store, self.transport, self.engine, self.orchestrator = (
            store,
            transport,
            engine,
            orchestrator,
        )
        self.water = WaterPipeline(transport, engine)

    def revision(self, owner, farm_id, revision):
        farm = self.store.farm(owner, farm_id)
        with self.store.connection() as db:
            rows = db.execute(
                "SELECT revision FROM farm_links WHERE owner=? AND farm_id=?",
                (owner, str(farm_id)),
            ).fetchall()
        if not any(datetime.fromisoformat(r[0]) == revision for r in rows):
            raise PlatformError("CONFIRMED_FARM_REVISION_REQUIRED", 409)
        return farm

    def list(self, owner, farm_id, table):
        if table not in {"historical_windows", "historical_simulations"}:
            raise ValueError("Internal table only")
        self.store.farm(owner, farm_id)
        if table == "historical_simulations":
            with self.store.connection() as db:
                return [
                    dict(r)
                    for r in db.execute(
                        "SELECT id, farm_id, json_extract(document,'$.revision') AS revision, "
                        "json_extract(document,'$.request.name') AS name, "
                        "json_extract(document,'$.created_at') AS created_at, "
                        "json_extract(document,'$.calculation_sha256') AS calculation_sha256 "
                        "FROM historical_simulations WHERE farm_id=? AND owner=? ORDER BY created DESC LIMIT 100",
                        (str(farm_id), owner),
                    )
                ]
        with self.store.connection() as db:
            return [
                json.loads(r[0])
                for r in db.execute(
                    f"SELECT document FROM {table} WHERE farm_id=? AND owner=? ORDER BY created DESC LIMIT 100",
                    (str(farm_id), owner),
                )
            ]

    def get(self, owner, farm_id, ident, table="historical_windows"):
        if table not in {"historical_windows", "historical_simulations"}:
            raise ValueError("Internal table only")
        self.store.farm(owner, farm_id)
        with self.store.connection() as db:
            row = db.execute(
                f"SELECT document FROM {table} WHERE id=? AND farm_id=? AND owner=?",
                (str(ident), str(farm_id), owner),
            ).fetchone()
        if row is None:
            raise PlatformError("NOT_FOUND", 404)
        return json.loads(row[0])

    def _insert(self, owner, value, table, key=None):
        raw = encoded(value)
        if len(raw.encode()) > 4_000_000:
            raise PlatformError("HISTORICAL_RESULT_TOO_LARGE", 413)
        with self.store.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            self.store.farm(owner, value["farm_id"], db)
            if (
                db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                >= self.store.max_rows
            ):
                raise PlatformError("STORAGE_QUOTA", 507)
            values = (value["id"], value["farm_id"], owner)
            if key is not None:
                values += (key,)
            placeholders = ",".join("?" for _ in range(len(values) + 2))
            db.execute(
                f"INSERT INTO {table} VALUES ({placeholders})",
                (*values, raw, time.time()),
            )
            self.store._audit(db, owner, value["id"], table + ".saved", VERSION)
        return value

    async def retrieve(self, owner, raw):
        q = ArchiveInput.model_validate(raw)
        farm = self.revision(owner, q.farm_id, q.revision)
        key = digest(q.model_dump(mode="json", exclude={"refresh"}))
        if not q.refresh:
            with self.store.connection() as db:
                row = db.execute(
                    "SELECT document FROM historical_windows WHERE request_key=? AND owner=? ORDER BY created DESC LIMIT 1",
                    (key, owner),
                ).fetchone()
            if row:
                return {**json.loads(row[0]), "source_mode": "cached_real"}
        query = ClimateQuery(point=farm.confirmed_point, start=q.start, end=q.end)
        source_key = cache_key(
            "NASA POWER", "historical-inputs", VERSION, query.model_dump(mode="json")
        )
        captured = None if q.refresh else self.store.cache_get(source_key)
        hit = captured is not None
        if captured is None:
            captured = await self.water.retrieve(query)
            try:
                capture = await self.transport.get(
                    ENDPOINT,
                    {
                        "parameters": "T2M",
                        "community": "AG",
                        "latitude": query.point.latitude,
                        "longitude": query.point.longitude,
                        "start": q.start.strftime("%Y%m%d"),
                        "end": q.end.strftime("%Y%m%d"),
                        "format": "JSON",
                        "time-standard": "LST",
                    },
                )
                captured["records"].append(
                    read_daily(
                        capture, query, "T2M", contract=MEAN_CONTRACT
                    ).model_dump(mode="json")
                )
            except PlatformError as exc:
                captured["gaps"].append(
                    {"parameter": "T2M", "code": exc.code, "retryable": exc.retryable}
                )
            if captured["records"] and not captured["gaps"]:
                self.store.cache_put(source_key, captured, ttl=365 * 86400)
        if not captured["records"]:
            raise PlatformError("NO_VALID_HISTORICAL_EVIDENCE", 503, True)
        # Keep the accepted WaterPipeline parameter set unchanged.
        parents = [
            r
            for r in captured["records"]
            if r["source_metadata"]["parameter"] in PARAMS
        ]
        calculated = await self.water.calculate(parents, query)
        records = [*captured["records"], calculated.model_dump(mode="json")]
        for r in records:
            self.store.save_evidence(owner, Evidence.model_validate(r), q.farm_id)
        now = datetime.now(timezone.utc).isoformat()
        value = {
            "schema_version": VERSION,
            "id": str(uuid4()),
            "farm_id": str(q.farm_id),
            "revision": q.revision.isoformat(),
            "start": str(q.start),
            "end": str(q.end),
            "created_at": now,
            "source_mode": "cached_real" if hit else "real",
            "day_basis": "NASA_POWER_LST",
            "evidence_ids": [r["id"] for r in records],
            "source_hashes": {r["id"]: r["response_sha256"] for r in records},
            "retrieved_at": {r["id"]: r["temporal"]["retrieved_at"] for r in records},
            "gaps": captured["gaps"],
            "summary": summary(records, q.start, q.end),
            "monthly": monthly(records, q.start, q.end),
            "engine_binary_sha256": self.engine.sha256,
            "scientific_eligibility_changed": False,
        }
        return self._insert(owner, value, "historical_windows", key)

    def records(self, owner, farm_id, archive):
        return [
            self.store.evidence(owner, ident, farm_id)
            for ident in archive["evidence_ids"]
        ]

    def replay(self, owner, farm_id, ident):
        archive = self.get(owner, farm_id, ident)
        records = self.records(owner, farm_id, archive)
        return {**archive, "records": [r.model_dump(mode="json") for r in records]}

    async def simulate(self, owner, raw):
        q = SimulationInput.model_validate(raw)
        farm = self.revision(owner, q.farm_id, q.revision)
        request = q.model_dump(mode="json")
        try:
            old = self.get(owner, q.farm_id, q.id, "historical_simulations")
        except PlatformError as exc:
            if exc.code != "NOT_FOUND":
                raise
        else:
            if old["request"] != request:
                raise PlatformError("IMMUTABLE_SIMULATION_CONFLICT", 409)
            return old
        if q.parent_id:
            self.get(owner, q.farm_id, q.parent_id, "historical_simulations")
        if q.comparison_id:
            if any(len(s.plans) < 2 for s in q.strategies):
                raise PlatformError("SAVED_ROTATION_SEQUENCE_REQUIRED", 422)
            from .comparisons import Comparisons

            if str(q.comparison_id) not in {
                c["id"] for c in Comparisons(self.store).list(owner, farm.id)
            }:
                raise PlatformError("COMPARISON_NOT_OWNED_BY_FARM", 404)
        archives = [self.get(owner, farm.id, ident) for ident in q.archive_ids]
        if any(datetime.fromisoformat(a["revision"]) != q.revision for a in archives):
            raise PlatformError("FARM_REVISION_MISMATCH", 409)
        # One unambiguous pinned record per variable/day, including adjacent
        # annual archives for seasons crossing a calendar year.
        records = []
        seen = set()
        for a in archives:
            for r in self.records(owner, farm.id, a):
                if r.id not in seen:
                    seen.add(r.id)
                    records.append(r)
        basis = q.periods[0]
        period_results, decisions = [], []
        for period in q.periods:
            delta = period.start.year - basis.start.year

            def shift(day):
                if (period.start.month, period.start.day) == (
                    basis.start.month,
                    basis.start.day,
                ):
                    return day.replace(year=day.year + delta)
                return day + (period.start - basis.start)

            shifted = []
            try:
                for s in q.strategies:
                    plans = [
                        p.model_copy(
                            update={
                                "start": shift(p.start),
                                "end": shift(p.end),
                            }
                        )
                        for p in s.plans
                    ]
                    intervals = [
                        p.model_copy(
                            update={
                                "start": shift(p.start),
                                "end": shift(p.end),
                            }
                        )
                        for p in s.intervals
                    ]
                    if any(
                        p.start < period.start or p.end > period.end
                        for p in [*plans, *intervals]
                    ):
                        raise ValueError("Mapped dates outside comparison season")
                    shifted.append((s, plans, intervals))
            except ValueError as exc:
                raise PlatformError("SEASON_DATE_MAPPING_REQUIRES_REVIEW", 422) from exc
            stats = summary(records, period.start, period.end, as_of=q.decision_at)
            strategies = []
            for s, plans, intervals in shifted:
                # Project pinned archive records to a single season so existing
                # Rust evidence contracts remain bounded and unambiguous.
                projected_ids = self._project(
                    owner, farm.id, records, period, q.decision_at
                )
                assessment = await self.orchestrator.assess(
                    owner,
                    AssessmentInput(
                        farm_id=farm.id,
                        catalog_version="v2",
                        evidence_ids=projected_ids,
                        plans=plans,
                        sequential_field=True,
                        start=period.start,
                        end=period.end,
                    ),
                    as_of=q.decision_at,
                )
                decisions.append(assessment["decision_id"])
                calendar = calendar_intervals(
                    [],
                    [
                        {
                            "id": f"plan:{i}",
                            "kind": "season",
                            "occurred_on": str(p.start),
                            "harvest_on": str(p.end),
                            "crop_id": p.profile_id,
                            "crop_name": p.profile_id,
                        }
                        for i, p in enumerate(plans)
                    ]
                    + [
                        {
                            "id": f"interval:{i}",
                            "kind": p.kind,
                            "occurred_on": str(p.start),
                            "harvest_on": str(p.end),
                            "crop_id": None,
                            "crop_name": p.kind,
                        }
                        for i, p in enumerate(intervals)
                    ],
                )
                water = water_dependencies(farm.production_system)
                strategies.append(
                    {
                        "identity": s.identity,
                        "classification": "simulated",
                        "plans": [
                            {
                                **p.model_dump(mode="json"),
                                "duration_days": (p.end - p.start).days + 1,
                                "environment": summary(
                                    records, p.start, p.end, as_of=q.decision_at
                                ),
                            }
                            for p in plans
                        ],
                        "assumptions": s.assumptions.model_dump(),
                        "assumption_review": {
                            "water_supply_declared": s.assumptions.irrigation
                            != "unknown",
                            "drainage_declared": s.assumptions.drainage != "unknown",
                            "hydrological_effect_calculated": False,
                            "explanation": "Declared supply/drainage changes the recorded constraints, not rainfall, reference ET0 or an unvalidated water balance.",
                        },
                        "calendar": calendar,
                        "decision_id": assessment["decision_id"],
                        "rust_findings": assessment["result"]["data"]["findings"],
                        "rust_summaries": assessment["result"]["data"]["summaries"],
                        "crop_references": assessment["catalog_projection"]
                        if q.mode == "retrospective"
                        else [],
                        "water_quantities": water,
                        "priority_alignment": [
                            {
                                "priority": p,
                                "status": "requires_applicable_crop_and_field_evidence",
                            }
                            for p in q.priorities
                        ],
                    }
                )
            period_results.append(
                {
                    **stats,
                    "monthly": monthly(
                        records, period.start, period.end, as_of=q.decision_at
                    ),
                    "strategies": strategies,
                }
            )
        saved_comparisons = []
        if q.comparison_id:
            from .comparisons import Comparisons, ComparisonInput

            for period_result in period_results:
                ids = {
                    s["identity"]: s["decision_id"] for s in period_result["strategies"]
                }
                saved = Comparisons(self.store).save(
                    owner,
                    farm.id,
                    ComparisonInput(
                        id=uuid4(),
                        name=(q.name + " historical reassessment")[:150],
                        baseline_decision_id=ids["baseline"],
                        alternative_decision_ids=[
                            ids["alternative_a"],
                            ids["alternative_b"],
                        ],
                        baseline_declared_existing_plan=True,
                        priorities=q.priorities,
                        practical_constraints="Hypothetical historical replay; per-strategy assumptions preserved in simulation result.",
                        exploration_reason="Retrospective reassessment of existing comparison "
                        + str(q.comparison_id),
                    ),
                )
                saved_comparisons.append(saved["id"])
        core = {
            "request": request,
            "periods": period_results,
            "baseline": contextual_baseline(period_results),
            "source_lineage": [
                {
                    "evidence_id": r.id,
                    "sha256": r.response_sha256,
                    "dataset": r.dataset,
                    "version": r.dataset_version,
                    "retrieved_at": r.temporal.retrieved_at.isoformat(),
                    "publication_at": r.temporal.issued_at.isoformat()
                    if r.temporal.issued_at
                    else None,
                }
                for r in records
            ],
            "engine_binary_sha256": self.engine.sha256,
        }
        # Server-generated result/decision IDs, names and creation time do not
        # participate in the reproducible calculation digest.
        stable = json.loads(encoded(core))
        for k in ("id", "parent_id", "name", "comparison_id"):
            stable["request"].pop(k, None)
        for p in stable["periods"]:
            for s in p["strategies"]:
                s.pop("decision_id")
        value = {
            "schema_version": "earthsync.simulation-result.v1",
            "id": str(q.id),
            "farm_id": str(farm.id),
            "revision": q.revision.isoformat(),
            "created_at": datetime.now(timezone.utc).isoformat(),
            **core,
            "calculation_sha256": digest(stable),
            "saved_comparison_ids": saved_comparisons,
            "classification": "simulated",
            "environmental_classification": "cached_real" if records else "unavailable",
            "recommendation_eligible": False,
            "unavailable_outputs": [
                "yield",
                "soil_nutrient_change",
                "ETc",
                "irrigation_requirement",
                "disease_rate",
                "suitability_percentage",
            ],
            "as_of_limitations": [
                "Only observations ending before decision day and archived retrievals on/before the decision timestamp are eligible.",
                "Historical publication timestamps are unknown unless explicitly preserved. Present-day retrieval is not proof of historical availability.",
                "Current reference identities support chronology mechanics only; crop traits are withheld in as-of mode.",
            ]
            if q.decision_at
            else [],
            "limitations": [
                "Retrospective what-if analysis using the archive now available; not a forecast.",
                "Partial subtotals never stand for complete-period totals.",
                "60 blocked crop rules remain disabled. No crop suitability or field-health prediction.",
            ],
        }
        return self._insert(owner, value, "historical_simulations")

    def _project(self, owner, farm_id, records, period, as_of):
        """Reuse Evidence sidecars without splicing incompatible source versions."""
        result = []
        if as_of is not None:
            as_of = as_of.astimezone(timezone.utc)
        for variable in ("rainfall", "tmin", "tmax", "et0"):
            selected = [
                r
                for r in records
                if r.measurements
                and r.measurements[0].variable == variable
                and r.temporal.start <= period.end
                and r.temporal.end >= period.start
                and (as_of is None or r.temporal.retrieved_at <= as_of)
            ]
            if not selected:
                continue
            # Entire-period source is passed directly. Adjacent annual archives
            # are combined only when no dates overlap; parent identity persists.
            measurements = []
            seen = set()
            for r in selected:
                for m in r.measurements:
                    if not period.start <= m.date <= period.end or (
                        as_of and m.date >= as_of.date()
                    ):
                        continue
                    if m.date in seen:
                        raise PlatformError("AMBIGUOUS_EVIDENCE", 422)
                    seen.add(m.date)
                    measurements.append(m)
            if not measurements:
                continue
            base = selected[0]
            if any(
                r.dataset_version != base.dataset_version
                or r.source_metadata.get("policy") != base.source_metadata.get("policy")
                or r.temporal.day_basis != base.temporal.day_basis
                for r in selected
            ):
                raise PlatformError("INCOMPATIBLE_HISTORICAL_SOURCES", 422)
            raw = base.model_dump(mode="json")
            raw["measurements"] = [
                m.model_dump(mode="json")
                for m in sorted(measurements, key=lambda m: m.date)
            ]
            raw["temporal"].update(
                start=str(period.start),
                end=str(period.end),
                retrieved_at=max(r.temporal.retrieved_at for r in selected).isoformat(),
            )
            raw["source_metadata"] = {
                "policy": base.source_metadata["policy"],
                "parameter": base.source_metadata["parameter"],
                "parent_evidence_ids": [r.id for r in selected],
                "parent_response_sha256": {r.id: r.response_sha256 for r in selected},
                "projection": "bounded historical period; no values imputed",
                "engine_binary_sha256": self.engine.sha256
                if variable == "et0"
                else None,
            }
            raw["response_sha256"] = digest(
                {
                    "parents": raw["source_metadata"]["parent_response_sha256"],
                    "measurements": raw["measurements"],
                }
            )
            raw["id"] = "ev_" + digest(raw)
            projected = Evidence.model_validate(raw)
            self.store.save_evidence(owner, projected, farm_id)
            result.append(projected.id)
        return result
