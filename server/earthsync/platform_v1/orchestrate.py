"""Server-built engine input from owned records, retaining full sidecars."""

from datetime import date, datetime, timezone

from .errors import PlatformError
from .models import ENGINE_VERSION
from .water import water_dependencies


def engine_date(day):
    return {"year": day.year, "month": day.month, "day": day.day}


class Orchestrator:
    def __init__(self, store, engine, catalog, reference_catalog=None):
        self.store, self.engine, self.catalog = store, engine, catalog
        self.reference_catalog = reference_catalog

    async def assess(self, owner, query):
        farm = self.store.farm(owner, query.farm_id)
        records = [
            self.store.evidence(owner, ident, farm.id) for ident in query.evidence_ids
        ]
        request = {
            "schema_version": ENGINE_VERSION,
            "mode": "evidence_assessment",
            "day_basis": "NASA_POWER_LST",
            # A v2 profile's advisory region is not a located farm region.
            # Keep its exact scope in the reference sidecar, never relabel
            # an arbitrary global POWER point as that advisory zone.
            "region_id": query.pilot_id if query.catalog_version == "v1" else None,
            "approximate_user_location": None,
            "farm": {
                "field_id": str(farm.id),
                "point": farm.confirmed_point.model_dump(),
                "boundary": [
                    {"latitude": y, "longitude": x}
                    for x, y in farm.confirmed_polygon.coordinates[0][:-1]
                ]
                if farm.confirmed_polygon
                else None,
                "confirmed_on": engine_date(farm.confirmed_on),
            },
            "photos": [],
            "climate_intent": "historical",
            "sources": [],
            "catalog": [],
            "observations": [],
            "climate": [],
            "history_complete": False,
            "history": [],
            "scenarios": [],
            "sequential_field": query.sequential_field,
            "candidate_window": None,
        }
        gaps, projections = [], []
        seen_variables = set()
        for record in records:
            if (
                not record.usable_for_assessment
                or record.data_type != "modeled"
                or record.temporal.day_basis != request["day_basis"]
            ):
                gaps.append(
                    {"evidence_id": record.id, "code": "EVIDENCE_NOT_APPLICABLE"}
                )
                continue
            if (
                record.spatial.query_point != farm.confirmed_point
                or record.spatial.role != "regional_context"
            ):
                raise PlatformError("SPATIAL_MISMATCH")
            if record.temporal.start > query.start or record.temporal.end < query.end:
                gaps.append({"evidence_id": record.id, "code": "INCOMPLETE_PERIOD"})
                continue
            # Only the independently accepted daily adapter may feed this version.
            if record.source_metadata.get("policy") not in (
                "power-daily-merra2.v1",
                "power-fao56-inputs.v1",
                "fao56-daily-pm.v1",
            ):
                gaps.append(
                    {"evidence_id": record.id, "code": "UNSUPPORTED_SOURCE_LINEAGE"}
                )
                continue
            variables = {m.variable for m in record.measurements}
            if len(variables) != 1:
                raise PlatformError("SCHEMA_MISMATCH")
            variable = next(iter(variables))
            if variable not in {"tmin", "tmax", "rainfall", "et0"}:
                gaps.append(
                    {
                        "evidence_id": record.id,
                        "code": "RETAINED_WEATHER_INPUT_NOT_V03_VARIABLE",
                    }
                )
                continue
            if variable in seen_variables:
                raise PlatformError("AMBIGUOUS_EVIDENCE")
            seen_variables.add(variable)
            request["sources"].append(
                {
                    "id": record.id,
                    "title": record.dataset,
                    "citation": record.source_identifier,
                    "url": record.source_url,
                    "published_on": None,
                    "reviewed_on": None,
                    "review": "reference_only",
                    "limitations": record.limitations,
                }
            )
            request["climate"].append(
                {
                    "id": record.id + ":" + variable,
                    "day_basis": record.temporal.day_basis,
                    "variable": variable,
                    "unit": "celsius" if variable in ("tmin", "tmax") else "mm_per_day",
                    "provenance": {
                        "kind": record.data_type,
                        "source_ids": [record.id],
                        "period": {
                            "start": engine_date(record.temporal.start),
                            "end": engine_date(record.temporal.end),
                        },
                        "retrieved_on": engine_date(
                            record.temporal.retrieved_at.date()
                        ),
                        "issued_on": None,
                        "spatial": {
                            "scope": "regional",
                            "region_id": request["region_id"] or "power-query-context",
                            "resolution_m": None,
                        },
                        "quality": "usable",
                        "uncertainty": "Regional model; local applicability not independently verified",
                        "method": record.source_identifier,
                    },
                    "days": [
                        {
                            "date": engine_date(m.date),
                            "value": m.value,
                            "quality": m.quality,
                        }
                        for m in record.measurements
                    ],
                }
            )
        for variable in sorted({"tmin", "tmax", "rainfall", "et0"} - seen_variables):
            gaps.append({"variable": variable, "code": "MISSING_EVIDENCE"})
        for cycle in self.store.history(owner, farm.id):
            source_id = "farmer-history:" + cycle["id"]
            request["sources"].append(
                {
                    "id": source_id,
                    "title": "Farmer-reported crop history",
                    "citation": "Authorized local farm record",
                    "url": None,
                    "published_on": None,
                    "reviewed_on": None,
                    "review": "unreviewed",
                    "limitations": [
                        "Farmer report, not independent field validation; history completeness unknown."
                    ],
                }
            )
            period = {
                "start": engine_date(date.fromisoformat(cycle["start"])),
                "end": engine_date(date.fromisoformat(cycle["end"])),
            }
            request["history"].append(
                {
                    "id": cycle["id"],
                    "crop_id": cycle["crop_id"],
                    "profile_id": None,
                    "fallow": cycle["fallow"],
                    "period": period,
                    "provenance": {
                        "kind": "farmer_reported",
                        "source_ids": [source_id],
                        "period": period,
                        "retrieved_on": engine_date(
                            datetime.fromtimestamp(
                                cycle["reported_at"], timezone.utc
                            ).date()
                        ),
                        "issued_on": None,
                        "spatial": {"scope": "field", "field_id": str(farm.id)},
                        "quality": "usable",
                        "uncertainty": "Unverified farmer report",
                        "method": "explicit_farmer_history_record",
                    },
                }
            )
        profile_ids = list(
            dict.fromkeys(query.profile_ids + [p.profile_id for p in query.plans])
        )
        for ident in profile_ids:
            catalog = (
                self.reference_catalog
                if query.catalog_version == "v2"
                else self.catalog
            )
            if catalog is None:
                raise PlatformError("CATALOG_NOT_INSTALLED", 503)
            profile, sidecar = catalog.project(
                ident, query.pilot_id, farm.production_system
            )
            projections.append(sidecar)
            request["catalog"].append(profile)
            request["scenarios"].append(
                {
                    "id": "requested:" + ident,
                    "plans": [
                        {
                            "id": "plan:" + ident,
                            "crop_id": profile["crop_id"],
                            "profile_id": profile["id"],
                            "system": profile["system"],
                            "cultivar": profile["cultivar"],
                            "period": {
                                "start": engine_date(query.start),
                                "end": engine_date(query.end),
                            },
                        }
                    ],
                }
            )
        if query.plans:
            profiles = {p["id"]: p for p in request["catalog"]}
            request["scenarios"] = [
                {
                    "id": "requested_sequence",
                    "plans": [
                        {
                            "id": f"sequence-plan:{i}",
                            "crop_id": profiles[p.profile_id]["crop_id"],
                            "profile_id": p.profile_id,
                            "system": farm.production_system,
                            "cultivar": profiles[p.profile_id]["cultivar"],
                            "period": {
                                "start": engine_date(p.start),
                                "end": engine_date(p.end),
                            },
                        }
                        for i, p in enumerate(query.plans)
                    ],
                }
            ]
        if not profile_ids:
            gaps.append({"code": "NO_REVIEWED_CROP_REQUIREMENTS"})
        result = await self.engine.analyze(request)
        response = {
            "engine_version": ENGINE_VERSION,
            "engine_binary_sha256": self.engine.sha256,
            "assessed_at": datetime.now(timezone.utc).isoformat(),
            "recommendation_eligible": False,
            "result": result,
            "evidence_gaps": gaps,
            "catalog_projection": projections,
            "water_findings": water_dependencies(farm.production_system),
            "environmental_metrics": [
                r.source_metadata["calculation"]
                for r in records
                if r.source_metadata.get("policy") == "fao56-daily-pm.v1"
            ],
            "evidence": [r.model_dump(mode="json") for r in records],
            "limitations": [
                "Reference-only crop profiles cannot authorize recommendations.",
                "POWER LST growing periods need explicit farm-calendar applicability review.",
            ],
        }
        response["decision_id"] = self.store.save_decision(owner, farm.id, response)
        return response
