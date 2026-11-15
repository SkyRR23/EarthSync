"""Lossless reference handoff to v0.3, without manufacturing executable rules.

The current catalog contains no requirements with v0.3's exact statistics,
units/depth and review semantics. Empty rule sets are intentional and produce
Rust missing-information findings. The original graph remains in `reference`.
"""

import copy
import importlib.util
from datetime import date
from functools import lru_cache
from pathlib import Path

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from .errors import ServiceError
from .environmental.models import Point

ROOT = Path(__file__).resolve().parents[2] / "data/crop-knowledge/v1"
SYSTEMS = {
    "rainfed_upland": "rainfed",
    "dryland_winter_cereal": "dryland",
    "dryland_summer_cereal": "dryland",
    "irrigated_flooded_lowland": "flooded_lowland",
    "irrigated_upland": "irrigated",
}
VERSION = "earthsync.engine.v0.3.0"
LIMITATIONS = [
    "Reference-only source desk review is not agronomic verification.",
    "No catalog profile is recommendation-eligible or approved for candidates.",
    "Advisory dates are not hard planting limits; soil temperature is not air temperature.",
    "Daily climate, applicable soil depth/method, cultivar duration, stage Kc and reviewed numerical requirements are missing.",
    "Pilot selection is a research scope, not proof that a farm is inside that region.",
]


@lru_cache(maxsize=1)
def load_catalog():
    # Reuse the producer's schema AND semantic graph validation from a fixed,
    # versioned repository path. Never import a user path or modify sys.path.
    spec = importlib.util.spec_from_file_location(
        "earthsync_catalog_v1", ROOT / "tools/catalog.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validate(module.read_json(ROOT / "catalog.json"))


def profile_mapping(profile):
    if profile["recommendation_eligible"] is not False:
        raise ValueError(
            "This adapter only accepts the reviewed reference-only catalog"
        )
    system = SYSTEMS.get(profile["production_system"])
    if profile["kind"] == "fallow":
        return None, "Fallow is history/management, not an engine crop profile."
    if system is None:
        return (
            None,
            "Drill-sown delayed-flood management has no agreed v0.3 system mapping.",
        )
    family = profile["parameters"]["crop_family"]
    if family["state"] != "available" or not family["value"]:
        return None, "Crop family evidence is unavailable."
    return {
        "id": f"{profile['id']}@catalog-0.1.0",
        "crop_id": f"{profile['crop_id']}@catalog-0.1.0",
        "family": family["value"],
        "cultivar": profile["cultivar"],
        "system": system,
        "approved_for_candidates": False,
        "review": "reference_only",
        "rules": [],
    }, None


def catalog_view():
    catalog = load_catalog()
    mappings = []
    for profile in catalog["profiles"]:
        mapped, blocker = profile_mapping(profile)
        mappings.append(
            {
                "profile_id": profile["id"],
                "engine_profile": mapped,
                "blocker": blocker,
                "executable_requirements": 0,
            }
        )
    return {
        "schema_version": "earthsync.catalog-adapter.v1",
        "reference": catalog,
        "mappings": mappings,
        "limitations": LIMITATIONS,
    }


class Farm(BaseModel):
    model_config = ConfigDict(extra="forbid")
    field_id: str = Field(min_length=1, max_length=128)
    point: Point
    confirmed_on: date


class AssessmentQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")
    profile_id: str = Field(min_length=1, max_length=128)
    farm: Farm
    start: date
    end: date


def assessment_request(query: AssessmentQuery):
    if query.end < query.start or (query.end - query.start).days > 730:
        raise ServiceError(
            "INVALID_GROWING_PERIOD",
            "Choose an ordered growing period of at most two years.",
            422,
        )
    catalog = load_catalog()
    profile = next(
        (p for p in catalog["profiles"] if p["id"] == query.profile_id), None
    )
    if profile is None:
        raise ServiceError(
            "UNKNOWN_PROFILE", "Choose an existing catalog profile.", 422
        )
    mapped, blocker = profile_mapping(profile)
    if blocker:
        raise ServiceError("CATALOG_MAPPING_UNAVAILABLE", blocker, 422)

    def day(value):
        return {"year": value.year, "month": value.month, "day": value.day}

    sources = [
        {
            "id": source["id"],
            "title": source["title"],
            "citation": source["attribution"],
            "url": source["url"],
            # Partial publication precision must not become an invented exact day.
            "published_on": day(date.fromisoformat(source["publication_date"]))
            if source["publication_date_precision"] == "day"
            else None,
            "reviewed_on": None,
            "review": "reference_only",
            "limitations": [
                source["rights_note"],
                "Source desk review only; original date precision is preserved in reference.",
            ],
        }
        for source in catalog["sources"]
    ]
    request = {
        "schema_version": VERSION,
        "day_basis": "farmer-declared Gregorian calendar dates",
        "mode": "evidence_assessment",
        "region_id": profile["pilot_id"],
        "approximate_user_location": None,
        "farm": {
            "field_id": query.farm.field_id,
            "point": query.farm.point.model_dump(),
            "boundary": None,
            "confirmed_on": day(query.farm.confirmed_on),
        },
        "photos": [],
        "climate_intent": "historical",
        "sources": sources,
        "catalog": [mapped],
        "observations": [],
        "climate": [],
        "history_complete": False,
        "history": [],
        "sequential_field": True,
        "candidate_window": None,
        "scenarios": [
            {
                "id": "catalog-reference-assessment",
                "plans": [
                    {
                        "id": "farmer-declared-plan",
                        "crop_id": mapped["crop_id"],
                        "profile_id": mapped["id"],
                        "system": mapped["system"],
                        "cultivar": mapped["cultivar"],
                        "period": {"start": day(query.start), "end": day(query.end)},
                    }
                ],
            }
        ],
    }
    return {
        "request": request,
        "reference": copy.deepcopy(profile),
        "claims": catalog["claims"],
        "limitations": LIMITATIONS,
    }


router = APIRouter(prefix="/api/catalog/v1", tags=["reference-crop-catalog"])


@router.get("/profiles")
def profiles():
    return catalog_view()


@router.post("/assessment-request")
def build_assessment(query: AssessmentQuery):
    return assessment_request(query)
