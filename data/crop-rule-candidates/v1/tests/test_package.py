"""Scientific acceptance boundaries; software passes confer no agronomic approval."""

from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from jsonschema import Draft202012Validator, ValidationError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import package
from method_checks import example28_kc


class ReviewContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = package.load()
        cls.schema = package.read(package.ROOT / "package.schema.json")
        cls.facts = {f["id"]: f for f in package.read(package.ROOT / "facts.json")}
        cls.candidates = {c["id"]: c for c in cls.data["candidates"]}
        cls.evidence = package.read(package.ROOT / "upstream-evidence.json")
        cls.claims = {c["id"]: c for c in cls.evidence["claims"]}

    def reject(self, path, value):
        changed = deepcopy(self.data)
        obj = changed
        for key in path[:-1]:
            obj = obj[key]
        obj[path[-1]] = value
        with self.assertRaises(ValidationError):
            Draft202012Validator(self.schema).validate(changed)

    def test_all_priority_domains_covered(self):
        self.assertEqual(len(self.candidates), 60)
        for crop in ["rice", "maize", "mung_bean", "sesame", "groundnut"]:
            self.assertEqual(
                sum(c.startswith("7v." + crop + ".") for c in self.candidates), 12
            )

    def test_package_cannot_become_recommendation_eligible(self):
        for flag in ["recommendation_eligible", "approved_for_candidates"]:
            with self.subTest(flag=flag):
                self.reject([flag], True)

    def test_candidates_cannot_be_promoted_by_mechanical_success(self):
        for flag in ["recommendation_eligible", "approved_for_candidates"]:
            with self.subTest(flag=flag):
                self.reject(["candidates", 0, flag], True)

    def test_no_executable_payload_or_field_approval(self):
        self.reject(["executable_rules"], [{"condition": "duration"}])
        self.reject(
            ["candidates", 0, "proposed_requirement"],
            {"condition": "duration", "range_days": {"min": 90, "max": 100}},
        )
        self.reject(["candidates", 0, "execution_status"], "accepted")
        self.reject(
            ["candidates", 0, "review", "applicable_rule_independently_reviewed"], True
        )
        self.reject(
            ["candidates", 0, "review", "needs_agronomist_field_validation"], False
        )

    def test_strict_schema_unknown_fields_and_types(self):
        self.reject(["rust_catalog"], [])
        self.reject(["candidates", 0, "review", "source_fact"], "approved")
        self.reject(["approved_for_candidates"], "false")
        self.reject(["candidates"], self.data["candidates"][:-1])

    def test_strict_json_rejects_duplicates_and_nonfinite(self):
        for text in ['{"a":1,"a":2}', '{"x":NaN}', '{"x":Infinity}']:
            with self.subTest(text=text), tempfile.TemporaryDirectory() as temp:
                path = Path(temp) / "bad.json"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    package.read(path)

    def test_disk_promotion_rejected_by_actual_loader(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "review-package"
            shutil.copytree(
                package.ROOT, root, ignore=shutil.ignore_patterns("__pycache__")
            )
            changed = deepcopy(self.data)
            changed["candidates"][0]["approved_for_candidates"] = True
            (root / "package.json").write_bytes(package.encoded(changed))
            with (
                patch.object(package, "ROOT", root),
                self.assertRaisesRegex(ValueError, "Package drift"),
            ):
                package.load()

    def test_upstream_drift_rejected_before_rebuild(self):
        original = package.digest
        with patch.object(
            package,
            "digest",
            side_effect=lambda path: "0" * 64
            if path.name == "catalog.json"
            else original(path),
        ):
            with self.assertRaisesRegex(ValueError, "Pinned input changed"):
                package.generate()

    def test_fact_cannot_self_certify_independent_applicability(self):
        fact = deepcopy(self.facts["groundnut.erect"])
        fact["independent_applicability_status"] = "approved"
        with self.assertRaises(ValidationError):
            Draft202012Validator(self.schema["$defs"]["fact"]).validate(fact)

    def test_all_profile_parameters_have_blocked_trace(self):
        trace = [
            json.loads(line)
            for line in (package.ROOT / "traceability.jsonl").read_text().splitlines()
        ]
        original = package.read(package.UPSTREAM / "mapping-report.json")
        self.assertEqual(len(trace), 1950)
        self.assertEqual(
            {(r["profile_id"], r["parameter"]) for r in trace},
            {(r["profile_id"], r["parameter"]) for r in original},
        )
        self.assertTrue(all(r["status"] == "blocked" for r in trace))
        self.assertTrue(all(r["upstream_block_reason"] for r in trace))

    def test_exact_source_claim_units_dates_and_scope_retained(self):
        original = package.upstream()
        original_claims = {c["id"]: c for c in original["claims"]}
        for claim in self.evidence["claims"]:
            self.assertEqual(claim, original_claims[claim["id"]])
        for candidate in self.candidates.values():
            self.assertTrue(set(candidate["claim_ids"]) <= self.claims.keys())
            self.assertTrue(set(candidate["fact_ids"]) <= self.facts.keys())
            self.assertTrue(candidate["required_evidence"])
            self.assertTrue(candidate["uncertainty"])

    def test_original_authority_and_exact_locators_for_new_facts(self):
        sources = {s["id"]: s for s in package.read(package.ROOT / "sources.json")}
        receipts = {
            r["id"]: r for r in package.read(package.ROOT / "source-receipts.json")
        }
        for fact in self.facts.values():
            source = sources[fact["source_id"]]
            receipt = receipts[source["receipt_id"]]
            self.assertEqual(source["publisher"], "FAO")
            self.assertEqual(len(receipt["sha256"]), 64)
            self.assertLessEqual(receipt["started_at"], receipt["completed_at"])
            for key in [
                "locator",
                "claim",
                "unit",
                "statistic",
                "geographic_applicability",
                "production_system",
                "limitations",
                "uncertainty",
            ]:
                self.assertTrue(fact[key])
            self.assertEqual(fact["independent_applicability_status"], "not_approved")

    def test_annual_rainfall_cannot_be_prorated_into_season_rule(self):
        for crop in ["rice", "maize", "mung_bean", "sesame", "groundnut"]:
            c = self.candidates[f"7v.{crop}.growing_period_rainfall@1"]
            self.assertIsNone(c["proposed_requirement"])
            self.assertIn("Annual", c["block_reason"])
            annual = self.claims[crop + ".eco.annual_precipitation"]
            self.assertEqual(annual["unit"], "mm")
            self.assertIn("annual", annual["statistic"].lower())

    def test_average_temperature_not_daily_or_monthly_extreme(self):
        for crop in ["rice", "maize", "mung_bean", "sesame", "groundnut"]:
            self.assertIn(
                "average minimum/maximum",
                self.claims[crop + ".eco.ecological_temperature"]["statistic"],
            )
            c = self.candidates[f"7v.{crop}.temperature@1"]
            self.assertIn("each daily extreme", c["block_reason"])
            self.assertIsNone(c["proposed_requirement"])

    def test_calendar_dates_keep_aez_and_old_update(self):
        calendar = [
            c for c in self.claims.values() if c["source_id"] == "fao_calendar_mm"
        ]
        self.assertTrue(calendar)
        self.assertTrue(all(c["region_id"].startswith("MM-FAO-AEZ-") for c in calendar))
        self.assertTrue(all("2021-02-26" in c["temporal_support"] for c in calendar))
        self.assertTrue(
            all(
                c["value"]["advisory"]
                for c in calendar
                if c["parameter"] == "planting_window"
            )
        )

    def test_identity_conflicts_do_not_resolve_by_duration(self):
        for crop, word in [("maize", "sweet"), ("mung_bean", "Penauk")]:
            c = self.candidates[f"7v.{crop}.planting_window@1"]
            self.assertIn(word, " ".join(c["contradictions_and_limits"]))
            self.assertEqual(c["execution_status"], "blocked")

    def test_groundnut_type_and_months_not_conflated(self):
        fact = self.facts["groundnut.erect"]
        self.assertEqual(
            fact["value"], {"erect_days": [90, 100], "prostrate_months": [5, 6]}
        )
        self.assertIsNone(fact["cultivar"])
        self.assertIn("Inclusive", " ".join(fact["limitations"]))

    def test_sesame_source_arithmetic_disagreement_remains_blocked(self):
        row = self.facts["sesame.stage.1"]["value"]
        self.assertEqual(row["stage_lengths_days"], [20, 30, 40, 20])
        self.assertEqual(row["stated_total_days"], 100)
        self.assertEqual(row["stage_sum_days"], 110)
        self.assertEqual(
            self.candidates["7v.sesame.stage_duration@1"]["execution_status"], "blocked"
        )

    def test_stage_rows_retain_region_and_planting_context(self):
        rows = [f for f in self.facts.values() if ".stage." in f["id"]]
        self.assertEqual(len(rows), 13)
        for row in rows:
            self.assertEqual(
                sum(row["value"]["stage_lengths_days"]), row["value"]["stage_sum_days"]
            )
            self.assertTrue(row["geographic_applicability"])
            self.assertTrue(row["value"]["planting_context"])
        self.assertEqual(
            self.facts["maize.stage.3"]["geographic_applicability"], "Nigeria (humid)"
        )

    def test_kc_harvest_alternatives_are_not_confidence_intervals(self):
        for crop, expected in [
            ("maize", {"min": 0.35, "max": 0.6}),
            ("mung_bean", {"min": 0.35, "max": 0.6}),
            ("rice", {"min": 0.6, "max": 0.9}),
        ]:
            fact = self.facts[crop + ".kc"]
            self.assertEqual(fact["value"]["end"], expected)
            self.assertIn("not confidence intervals", fact["claim"])

    def test_group_initial_is_only_an_approximation(self):
        self.assertEqual(self.facts["method.group_initial"]["value"]["cereals"], 0.3)
        self.assertIsNone(self.facts["maize.kc"]["value"]["initial"])
        self.assertIn("planning", self.facts["method.group_initial"]["claim"])

    def test_flooded_rice_not_upland_or_flood_tolerance(self):
        rice = [
            p for p in self.evidence["profiles"] if p["crop_id"] == "ecocrop.1574@1"
        ]
        systems = {p["production_system"] for p in rice}
        self.assertTrue(
            {
                "rainfed_upland",
                "flooded_irrigated_lowland",
                "irrigated_drill_sown_delayed_flood",
            }
            <= systems
        )
        self.assertIn("0.10–0.20 m", " ".join(self.facts["rice.kc"]["limitations"]))
        self.assertIsNone(
            self.candidates["7v.rice.flood_tolerance@1"]["target_condition"]
        )

    def test_soil_method_depth_and_maize_missingness(self):
        self.assertFalse(
            any(
                c.startswith("maize.eco.soil_texture")
                or c.startswith("maize.eco.soil_drainage")
                for c in self.claims
            )
        )
        for domain in ["soil_texture", "soil_drainage"]:
            self.assertTrue(
                self.candidates[f"7v.maize.{domain}@1"]["review"]["unsupported"]
            )
        self.assertIn(
            "chemical method", self.candidates["7v.rice.soil_ph@1"]["block_reason"]
        )

    def test_drought_stage_labels_never_become_offsets_or_injury(self):
        fact = self.facts["maize.water_sensitivity"]
        self.assertIn("flowering and grain filling", fact["claim"])
        self.assertIsNone(
            self.candidates["7v.maize.drought_stage_sensitivity@1"]["target_condition"]
        )
        for crop in ["mung_bean", "sesame"]:
            self.assertTrue(
                self.candidates[f"7v.{crop}.drought_stage_sensitivity@1"]["review"][
                    "unsupported"
                ]
            )

    def test_rotation_not_intercropping_or_elapsed_gap(self):
        self.assertIn(
            "Do not turn intercropping into ordered succession",
            " ".join(self.facts["rotation.cereal"]["limitations"]),
        )
        for c in self.candidates.values():
            if c["domain"] == "succession":
                self.assertIn("not proof of fallow", " ".join(c["required_evidence"]))
                self.assertIsNone(c["proposed_requirement"])

    def test_upstream_profiles_remain_quarantined(self):
        for p in package.upstream()["profiles"]:
            self.assertEqual(p["review"], "reference_only")
            self.assertFalse(p["approved_for_candidates"])
            self.assertFalse(p["recommendation_eligible"])
            self.assertEqual(p["executable_rules"], [])


class PublishedNumericalChecks(unittest.TestCase):
    def test_example28_published_four_day_values(self):
        for day, value in {20: "0.15", 40: "0.77", 70: "1.19", 95: "0.56"}.items():
            with self.subTest(day=day):
                self.assertEqual(
                    example28_kc(day).quantize(Decimal("0.01")), Decimal(value)
                )

    def test_curve_boundaries_and_daily_day_convention(self):
        self.assertEqual(
            [example28_kc(i) for i in [1, 25, 50, 80, 100]],
            list(map(Decimal, ["0.15", "0.15", "1.19", "1.19", "0.35"])),
        )
        for bad in [0, 101, -1, True, 25.5]:
            with self.subTest(day=bad), self.assertRaises(ValueError):
                example28_kc(bad)

    def test_constant_development_or_late_stage_changes_published_method(self):
        self.assertNotEqual(example28_kc(40), example28_kc(50))
        self.assertNotEqual(example28_kc(95), example28_kc(80))
        # A daily encoding could preserve Eq.66; no candidate encoding is approved.
        daily = [example28_kc(i) for i in range(1, 101)]
        # Closed-form arithmetic progression sums: 3.75 + 17.27 + 35.70 + 14.98.
        self.assertEqual(sum(daily), Decimal("71.70"))
        self.assertEqual(sum(k * Decimal(5) for k in daily), Decimal("358.50"))


if __name__ == "__main__":
    unittest.main()
