"""Adapter for PR #15, intentionally excludes unapproved numerical rules."""

import hashlib
import json
from pathlib import Path

from .errors import PlatformError

SYSTEMS = {
    "rainfed_upland": "rainfed",
    "dryland": "dryland",
    "dryland_summer_cereal": "dryland",
    "dryland_winter_cereal": "dryland",
    "irrigated_drill_sown_delayed_flood": "flooded_lowland",
    "irrigated_upland": "irrigated",
    "irrigated_flooded_lowland": "flooded_lowland",
    "irrigated_lowland": "flooded_lowland",
}


class Catalog:
    def __init__(self, path=None, expected_sha256=None):
        self.data, self.sha256 = None, None
        if path:
            raw = Path(path).read_bytes()
            self.sha256 = hashlib.sha256(raw).hexdigest()
            if not expected_sha256 or self.sha256 != expected_sha256:
                raise ValueError("Catalog requires an exact reviewed artifact hash")
            data = json.loads(raw)
            if (
                data.get("schema_version") != "earthsync.crop-knowledge.v1-proposal"
                or data.get("recommendation_eligible") is not False
            ):
                raise ValueError(
                    "Unsupported catalog contract or recommendation eligibility"
                )
            if any(
                p.get("recommendation_eligible") is not False for p in data["profiles"]
            ):
                raise ValueError("Current adapter only accepts reference profiles")
            self.data = data

    def lookup(self, profile_id):
        if self.data is None:
            raise PlatformError("CATALOG_NOT_INSTALLED", 503)
        matches = [p for p in self.data["profiles"] if p["id"] == profile_id]
        if len(matches) != 1:
            raise PlatformError("PROFILE_NOT_FOUND", 404)
        return matches[0]

    def project(self, profile_id, pilot_id, system):
        profile = self.lookup(profile_id)
        if profile["pilot_id"] != pilot_id:
            raise PlatformError("PROFILE_SCOPE_MISMATCH")
        if profile["kind"] == "fallow":
            raise PlatformError("FALLOW_IS_NOT_A_CROP_PROFILE")
        mapped = SYSTEMS.get(profile["production_system"])
        if mapped != system:
            raise PlatformError("PRODUCTION_SYSTEM_MISMATCH")
        family = profile["parameters"]["crop_family"]
        if family["state"] != "available" or not isinstance(family["value"], str):
            raise PlatformError("CROP_FAMILY_UNAVAILABLE")
        version = self.data["catalog_version"]
        return {
            "id": profile["id"],
            "crop_id": f"{profile['crop_id']}@catalog-{version}",
            "family": family["value"],
            "cultivar": profile["cultivar"],
            "system": system,
            "approved_for_candidates": False,
            "review": "reference_only",
            "rules": [],
        }, {
            "profile_id": profile["id"],
            "original_review_status": profile["review_status"],
            "original_production_system": profile["production_system"],
            "engine_production_system": system,
            "recommendation_eligible": False,
            "catalog_sha256": self.sha256,
            "unknown_properties": profile["unknown_properties"],
            "reason": "Source desk review and advisory calendars are not approved deterministic crop requirements; no numerical rules exported.",
        }
