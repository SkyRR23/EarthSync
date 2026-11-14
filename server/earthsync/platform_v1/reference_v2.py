"""Bounded read-only consumer of 7P's unchanged, independently tested interfaces."""

import copy
import hashlib
import importlib.util
from pathlib import Path

from .errors import PlatformError
from .agronomic_review import review_for

ROOT = Path(__file__).resolve().parents[3] / "data/crop-knowledge/v2"


class ReferenceCatalog:
    def __init__(self):
        spec = importlib.util.spec_from_file_location(
            "earthsync_crop_reference_v2", ROOT / "tools/knowledge.py"
        )
        self.api = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.api)
        self.data = self.api.load(ROOT)
        self.profiles = {p["id"]: p for p in self.data["profiles"]}
        self.sha256 = hashlib.sha256(self.api.encoded(self.data)).hexdigest()

    def lookup(self, query, region=None, system=None, cultivar=None):
        result = copy.deepcopy(
            self.api.lookup(self.data, query, region, system, cultivar)
        )
        for p in result.get("profiles", []):
            p["identity_projection_system"] = self.api.SYSTEMS.get(
                p["production_system"]
            )
            p["identity_projection_blocked"] = (
                "IDENTITY DISPUTED" in p["source_context"]
                or p["identity_projection_system"] is None
            )
        claim_ids = {
            c
            for p in result.get("profiles", [])
            for parameter in p["parameters"].values()
            for c in parameter["claim_ids"]
        }
        if result.get("crop"):
            claim_ids.add(result["crop"]["identity_claim_id"])
        result["claims"] = [
            copy.deepcopy(c) for c in self.data["claims"] if c["id"] in claim_ids
        ]
        source_ids = {
            s
            for c in result["claims"]
            for s in [c["source_id"], *c["supporting_source_ids"]]
        }
        result["sources"] = [
            copy.deepcopy(s) for s in self.data["sources"] if s["id"] in source_ids
        ]
        result["catalog_sha256"] = self.sha256
        if result.get("crop"):
            result["rule_review"] = review_for(result["crop"]["id"])
        return result

    def project(self, ident, region, farm_system):
        profile = self.profiles.get(ident)
        if profile is None:
            raise PlatformError("PROFILE_NOT_FOUND", 404)
        original_system = profile["production_system"]
        if profile["region_id"] != region:
            raise PlatformError("PROFILE_SCOPE_MISMATCH")
        if self.api.SYSTEMS.get(original_system) != farm_system:
            raise PlatformError("PRODUCTION_SYSTEM_MISMATCH")
        try:
            result = self.api.project(
                self.data, ident, region, original_system, profile["cultivar"]
            )
        except (ValueError, KeyError) as exc:
            raise PlatformError("REFERENCE_PROJECTION_BLOCKED") from exc
        result["sidecar"]["rule_review"] = review_for(result["profile"]["crop_id"])
        return result["profile"], result["sidecar"]
