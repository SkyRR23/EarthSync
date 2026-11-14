"""Offline provenance, producer-contract and scope regressions; no agronomic simulation."""

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from jsonschema.exceptions import ValidationError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import catalog


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bundle = catalog.build()

    def setUp(self):
        self.data = copy.deepcopy(self.bundle)
        self.corn = self.data["profiles"][0]

    def reject(self, message=None):
        with self.assertRaises((ValueError, ValidationError), msg=message):
            catalog.validate(self.data)

    def test_bundle_and_audit_are_reproducible(self):
        self.assertEqual(
            (catalog.ROOT / "catalog.json").read_bytes(), catalog.encoded(self.bundle)
        )
        self.assertEqual(
            catalog.read_json(catalog.ROOT / "audit.json"), catalog.audit(self.bundle)
        )
        self.assertEqual(catalog.build(), catalog.build())

    def test_captures_have_scoped_checksums_and_no_false_original_hash(self):
        audit = catalog.audit(self.bundle)
        self.assertIn("never original provider", audit["checksum_scope"])
        self.assertIn("evidence/captures.json", audit["checksums"])
        captures = catalog.read_json(catalog.ROOT / "evidence/captures.json")
        for capture in captures:
            self.assertIsNone(capture["provider_response_sha256"])
            self.assertEqual(capture["raw_response_status"], "unavailable")
            self.assertLessEqual(len(capture["excerpt"].split()), 25)

    def test_duplicate_ids_rejected_for_every_registry(self):
        for registry in ("sources", "claims", "profiles", "pilots"):
            with self.subTest(registry=registry):
                self.data = copy.deepcopy(self.bundle)
                self.data[registry].append(copy.deepcopy(self.data[registry][0]))
                self.reject()

    def test_missing_unknown_and_wrong_version_fields_rejected(self):
        for mutation in ("missing", "extra", "version"):
            with self.subTest(mutation=mutation):
                self.data = copy.deepcopy(self.bundle)
                if mutation == "missing":
                    del self.data["profiles"][0]["parameters"]["duration_days"]
                elif mutation == "extra":
                    self.data["profiles"][0]["suitability_score"] = 95
                else:
                    self.data["schema_version"] = "v0.2"
                self.reject()

    def test_unknown_never_becomes_zero(self):
        self.corn["parameters"]["duration_days"]["value"] = 0
        self.reject()

    def test_unknown_never_becomes_empty_string_or_empty_object(self):
        for value in ("", {}, []):
            with self.subTest(value=value):
                self.corn["parameters"]["water_management"]["value"] = value
                self.reject()

    def test_available_fact_cannot_be_null_or_uncited(self):
        fact = self.corn["parameters"]["scientific_name"]
        fact["value"] = None
        self.reject()
        fact["value"] = "Zea mays"
        fact["claim_ids"] = []
        self.reject()

    def test_unresolved_claim_rejected(self):
        self.corn["parameters"]["planting_window"]["claim_ids"] = ["missing"]
        self.reject()

    def test_unresolved_source_rejected(self):
        self.data["claims"][0]["source_id"] = "missing"
        self.reject()

    def test_unresolved_pilot_rejected(self):
        self.corn["pilot_id"] = "missing"
        self.reject()

    def test_regional_evidence_cannot_leak_to_another_pilot(self):
        target = self.data["profiles"][3]  # Tribune grain sorghum.
        target["parameters"]["planting_window"] = copy.deepcopy(
            self.corn["parameters"]["planting_window"]
        )
        target["unknown_properties"].remove("planting_window")
        self.reject()

    def test_production_system_scope_is_not_coerced(self):
        target = self.data["profiles"][5]  # Flooded Arkansas rice.
        claim = next(
            c for c in self.data["claims"] if c["id"] == "arkansas_flood_management"
        )
        claim["production_systems"] = ["irrigated_upland"]
        self.assertEqual(target["production_system"], "irrigated_flooded_lowland")
        self.reject()

    def test_taxonomy_cannot_cite_as_a_planting_rule(self):
        self.corn["parameters"]["planting_window"]["claim_ids"] = ["taxonomy_corn"]
        self.reject()

    def test_reference_only_cannot_be_promoted_to_reviewed(self):
        claim = next(c for c in self.data["claims"] if c["id"] == "iowa_corn_dates")
        claim["review_status"] = "reference_only"
        self.reject()

    def test_synthetic_cannot_enter_real_profiles(self):
        self.data["claims"][0]["evidence_kind"] = "synthetic"
        self.reject()

    def test_synthetic_review_status_cannot_enter_real_profiles(self):
        self.data["claims"][0]["review_status"] = "synthetic"
        self.corn["parameters"]["scientific_name"]["review_status"] = "reference_only"
        self.corn["parameters"]["crop_family"]["review_status"] = "reference_only"
        self.reject()

    def test_synthetic_parameter_cannot_enter_real_profiles(self):
        self.corn["parameters"]["scientific_name"]["review_status"] = "synthetic"
        self.reject()

    def test_calendar_without_either_endpoint_is_unavailable(self):
        self.corn["parameters"]["planting_window"]["value"].update(start=None, end=None)
        self.reject()

    def test_month_and_day_labels_are_validated(self):
        for invalid in ("00-01", "13-01", "04-31", "02-30", "annual"):
            with self.subTest(invalid=invalid):
                self.corn["parameters"]["planting_window"]["value"]["start"] = invalid
                self.reject()

    def test_software_only_cross_year_and_leap_day_cases(self):
        # Arbitrary calendar mechanics, never crop facts or pilot planting advice.
        value = self.corn["parameters"]["planting_window"]["value"]
        value.update(start="11-15", end="03-01", crosses_year=False)
        self.reject()
        value["crosses_year"] = True
        catalog.validate(self.data)
        self.assertEqual(catalog.month_day("02-29").day, 29)

    def test_one_sided_soybean_window_does_not_invent_start(self):
        value = self.bundle["profiles"][1]["parameters"]["planting_window"]["value"]
        self.assertIsNone(value["start"])
        self.assertEqual(value["end"], "05-20")
        self.assertEqual(value["meaning"], "advisory_not_hard_limit")

    def test_soil_temperature_is_not_air_temperature(self):
        parameters = self.corn["parameters"]
        value = parameters["soil_temperature_guidance"]["value"]
        self.assertEqual(value["medium"], "soil")
        self.assertEqual(value["threshold"], 50)
        self.assertIsNone(value["depth_cm"])
        self.assertIsNone(parameters["air_temperature_limits"]["value"])
        self.assertIsNone(parameters["soil_depth_cm"]["value"])
        value["medium"] = "air"
        self.reject()

    def test_incorrect_unit_rejected(self):
        self.corn["parameters"]["soil_temperature_guidance"]["unit"] = "degC"
        self.reject()

    def test_unknown_property_inventory_must_agree(self):
        self.corn["unknown_properties"] = []
        self.reject()

    def test_fallow_remains_distinct_from_a_crop(self):
        fallow = next(p for p in self.data["profiles"] if p["kind"] == "fallow")
        self.assertIsNone(fallow["crop_id"])
        self.assertEqual(
            fallow["parameters"]["scientific_name"]["state"], "not_applicable"
        )
        fallow["crop_id"] = "fallow"
        self.reject()

    def test_cli_can_select_fallow_without_inventing_a_crop_identity(self):
        result = subprocess.run(
            [
                sys.executable,
                str(catalog.ROOT / "tools/catalog.py"),
                "lookup",
                "--pilot",
                "us_ks_tribune",
                "--fallow",
                "--system",
                "dryland_fallow",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(result.stdout)
        self.assertEqual(output["state"], "available")
        self.assertEqual(output["profile"]["kind"], "fallow")
        self.assertIsNone(output["profile"]["crop_id"])
        self.assertFalse(output["recommendation_eligible"])

    def test_missing_evidence_cannot_be_reclassified_not_applicable(self):
        fact = self.corn["parameters"]["duration_days"]
        fact.update(state="not_applicable", review_status="not_applicable")
        self.corn["unknown_properties"].remove("duration_days")
        self.reject()

    def test_catalog_cannot_authorize_recommendations(self):
        self.corn["recommendation_eligible"] = True
        self.reject()

    def test_reversed_research_dates_rejected(self):
        interval = next(c for c in self.data["claims"] if c["id"] == "tribune_wsf")[
            "temporal_support"
        ]
        interval.update(start="2020-01-01", end="2008-01-01")
        self.reject()

    def test_publication_dates_are_not_retrieval_or_search_dates(self):
        source = next(s for s in self.data["sources"] if s["id"] == "isu_soil_2026")
        self.assertEqual(source["publication_date"], "2026-03-26")
        for invalid in ("2026-13-01", "2027-01-01", "2026-03"):
            with self.subTest(invalid=invalid):
                source["publication_date"] = invalid
                self.reject()

    def test_unavailable_numeric_bound_cannot_be_supported_without_a_bound(self):
        fact = self.corn["parameters"]["duration_days"]
        fact.update(
            state="available",
            value={"min": None, "max": None, "basis": "software test"},
            claim_ids=["iowa_corn_dates"],
            review_status="reviewed",
            reason=None,
        )
        claim = next(c for c in self.data["claims"] if c["id"] == "iowa_corn_dates")
        claim["parameter_keys"].append("duration_days")
        self.corn["unknown_properties"].remove("duration_days")
        self.reject()

    def test_lookup_retains_unknowns_and_does_not_extrapolate_globally(self):
        found = catalog.lookup(self.bundle, "us_ia_story", "corn", "rainfed_upland")
        self.assertEqual(found["state"], "available")
        self.assertFalse(found["recommendation_eligible"])
        for pilot, crop, system in (
            ("mm_yangon", "corn", "rainfed_upland"),
            ("us_ia_story", "rice", "rainfed_upland"),
            ("us_ia_story", "corn", "irrigated_upland"),
            ("au_nsw_riverina", "rice", "irrigated_flooded_lowland"),
        ):
            with self.subTest(pilot=pilot, crop=crop, system=system):
                result = catalog.lookup(self.bundle, pilot, crop, system)
                self.assertEqual(result["state"], "unavailable")
                self.assertIsNone(result["profile"])

    def test_pilot_cases_do_not_invent_farms_observations_or_photos(self):
        cases = catalog.pilot_cases(self.bundle)
        self.assertEqual(
            catalog.read_json(catalog.ROOT / "fixtures/pilot-cases.json"), cases
        )
        self.assertEqual(len(cases["cases"]), 4)
        for case in cases["cases"]:
            for key in (
                "user_approximate_location",
                "farmer_confirmed_farm",
                "field_photo",
            ):
                self.assertIsNone(case[key])
            self.assertEqual(case["environmental_evidence"]["state"], "unavailable")
            self.assertIsNone(case["environmental_evidence"]["value"])
            self.assertEqual(
                case["expected_recommendation_state"], "insufficient_information"
            )

    def test_strict_json_rejects_duplicate_keys_and_nonfinite_numbers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.json"
            for text in (
                '{"value":1,"value":2}',
                '{"value":NaN}',
                '{"value":Infinity}',
            ):
                with self.subTest(text=text):
                    path.write_text(text)
                    with self.assertRaises(ValueError):
                        catalog.read_json(path)


if __name__ == "__main__":
    unittest.main()
