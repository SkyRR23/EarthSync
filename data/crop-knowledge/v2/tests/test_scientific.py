"""Mechanical scientific-review safeguards, not an independent agronomic review."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from knowledge import ROOT, index, load, mapping_report, read_json


class ScientificSafeguards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = load()
        cls.profiles = index(cls.data["profiles"])

    def test_original_annual_water_meaning_is_retained(self):
        for label in ["rice", "mung_bean", "sesame", "groundnut", "maize"]:
            p = self.profiles[label + ".global.ecology@1"]
            annual = p["parameters"]["annual_precipitation"]
            self.assertEqual(annual["unit"], "mm")
            self.assertIn("Annual", annual["temporal_support"])
            self.assertIn("supplemental water", annual["statistic"])
            self.assertIsNone(p["parameters"]["growing_period_rainfall"]["value"])
            blocked = next(
                r for r in mapping_report(p) if r["parameter"] == "annual_precipitation"
            )
            self.assertIn("cannot be converted", blocked["reason"])

    def test_temperature_keeps_average_statistic(self):
        for p in self.data["profiles"]:
            t = p["parameters"]["ecological_temperature"]
            if t["state"] == "available":
                self.assertIn("average minimum/maximum", t["statistic"])
                self.assertIsNone(p["parameters"]["daily_extreme_temperature"]["value"])
                self.assertIn(
                    "daily Tmin/Tmax",
                    next(
                        r
                        for r in mapping_report(p)
                        if r["parameter"] == "ecological_temperature"
                    )["reason"],
                )

    def test_ecocrop_life_history_not_myanmar_duration(self):
        self.assertEqual(
            self.profiles["maize.global.ecology@1"]["parameters"][
                "ecological_crop_cycle"
            ]["value"]["max"],
            365,
        )
        self.assertIsNone(
            self.profiles["maize.global.ecology@1"]["parameters"]["growing_duration"][
                "value"
            ]
        )

    def test_soil_depth_is_not_sampling_depth(self):
        p = self.profiles["rice.global.ecology@1"]
        self.assertEqual(
            p["parameters"]["ecological_soil_depth"]["unit"], "source_category"
        )
        self.assertIsNone(p["parameters"]["soil_ph_by_depth"]["value"])
        self.assertIn(
            "sampling interval",
            next(
                r
                for r in mapping_report(p)
                if r["parameter"] == "ecological_soil_depth"
            )["reason"],
        )

    def test_calendar_profiles_do_not_inherit_ecological_requirements(self):
        for p in self.data["profiles"]:
            if ".calendar-" in p["id"]:
                self.assertIsNone(p["parameters"]["annual_precipitation"]["value"])
                self.assertIsNone(p["parameters"]["ecological_temperature"]["value"])
                self.assertIn(
                    "lastUpdated 2021-02-26",
                    p["parameters"]["planting_window"]["temporal_support"],
                )

    def test_rice_systems_are_distinct(self):
        systems = {
            p["production_system"]
            for p in self.data["profiles"]
            if p["crop_id"] == "ecocrop.1574@1"
        }
        self.assertTrue(
            {
                "flooded_irrigated_lowland",
                "rainfed_lowland",
                "rainfed_upland",
                "irrigated_drill_sown_delayed_flood",
            }
            <= systems
        )
        upland = self.profiles["rice.mm.rainfed-upland-research@1"]
        self.assertTrue(all(v["value"] is None for v in upland["parameters"].values()))

    def test_irrigated_calendar_label_does_not_establish_flooded_management(self):
        for p in self.data["profiles"]:
            if p["production_system"] == "irrigated_lowland_unspecified_management":
                self.assertIsNone(p["parameters"]["flooded_management"]["value"])
                self.assertIsNone(p["parameters"]["irrigation_requirements"]["value"])

    def test_kc_reference_has_no_executable_stage_offsets(self):
        for label in ["rice", "mung_bean", "sesame", "groundnut", "maize"]:
            p = self.profiles[label + ".global.fao56@1"]
            self.assertIsNone(p["parameters"]["kc_stages"]["value"]["stage_offsets"])
            self.assertEqual(p["executable_rules"], [])
            self.assertIsNone(p["parameters"]["water_demand"]["value"])
        self.assertIsNone(
            self.profiles["groundnut.global.fao56@1"]["parameters"]["kc_stages"][
                "value"
            ]["initial"]
        )
        self.assertIn(
            "fresh / 0.35 dry",
            self.profiles["mung_bean.global.fao56@1"]["parameters"]["kc_stages"][
                "value"
            ]["basis"],
        )

    def test_calendar_identity_disagreements_are_retained_separately(self):
        records = read_json(ROOT / "evidence/calendar-disagreements.json")
        self.assertTrue(any("0157" in r["reason"] for r in records))
        self.assertTrue(any("sweet-corn" in r["reason"] for r in records))
        mung = [
            p
            for p in self.data["profiles"]
            if p["crop_id"] == "ecocrop.2150@1" and ".calendar-" in p["id"]
        ]
        self.assertGreater(
            len(
                {
                    (
                        p["parameters"]["growing_duration"]["value"]["min"],
                        p["parameters"]["growing_duration"]["value"]["max"],
                    )
                    for p in mung
                }
            ),
            2,
        )
        self.assertTrue(all("IDENTITY DISPUTED" in p["source_context"] for p in mung))

    def test_erect_and_prostrate_groundnut_are_not_conflated(self):
        p = self.profiles["groundnut.mm.erect-type@1"]
        self.assertEqual(p["cultivar"], "erect_type_unspecified_variety")
        self.assertEqual(
            p["parameters"]["growing_duration"]["value"], {"min": 90, "max": 100}
        )
        claim = index(self.data["claims"])[
            p["parameters"]["growing_duration"]["claim_ids"][0]
        ]
        self.assertTrue(any("not converted" in text for text in claim["limitations"]))

    def test_rotation_dates_are_declared_software_examples(self):
        self.assertEqual(len(self.data["rotations"]), 8)
        for r in self.data["rotations"]:
            self.assertEqual(
                r["date_basis"], "synthetic_example_dates_not_source_calendar"
            )
            self.assertIsNone(r["verified_tradeoffs"])
            self.assertIsNone(r["water_requirements"])
            self.assertFalse(r["crop_history_available"])
            self.assertIsNone(r["succession_restrictions"])

    def test_taxonomy_never_creates_nitrogen_or_pest_credit(self):
        for p in self.data["profiles"]:
            self.assertEqual(p["executable_rules"], [])
            self.assertIsNone(p["parameters"]["succession"]["value"])

    def test_unreviewed_global_species_have_no_requirements(self):
        profiles = {p["crop_id"] for p in self.data["profiles"]}
        self.assertGreater(
            sum(c["id"] not in profiles for c in self.data["crops"]), 600
        )
        self.assertTrue(
            all(
                c["review"] == "reference_only"
                and c["recommendation_eligible"] is False
                and c["approved_for_candidates"] is False
                for c in self.data["crops"]
            )
        )

    def test_no_independent_agronomic_acceptance_claimed(self):
        for claim in self.data["claims"]:
            self.assertEqual(claim["review"], "reference_only")
            self.assertTrue(claim["limitations"])
            self.assertTrue(claim["uncertainty"])


if __name__ == "__main__":
    unittest.main()
