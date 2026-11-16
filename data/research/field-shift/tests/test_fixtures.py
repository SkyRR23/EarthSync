"""Regression evidence for this contributed capture, not scientific certification."""

import csv
import hashlib
import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("normalize", ROOT / "scripts" / "normalize.py")
normalizer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(normalizer)


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = {loc: json.loads((ROOT / "normalized" / f"{loc}.json").read_text())
                        for loc in ("hlegu", "bago", "magway")}

    def test_preservation_matches_archive_and_member_hashes(self):
        archive_path = ROOT / "raw" / "field-shift-data-pack.zip"
        inventory = json.loads((ROOT / "archive_inventory.json").read_text())
        self.assertEqual(hashlib.sha256(archive_path.read_bytes()).hexdigest(),
                         "f9d4eb2c5bcb6c73de5fc8bb17bc13a90241eee40715bf5522d369629b88f65c")
        self.assertEqual(inventory["archive_sha256"], hashlib.sha256(archive_path.read_bytes()).hexdigest())
        with zipfile.ZipFile(archive_path) as archive:
            self.assertEqual(set(archive.namelist()), {m["path"] for m in inventory["members"]})
            files = [m for m in inventory["members"] if m["kind"] == "file"]
            self.assertEqual(len(files), 62)
            for member in files:
                content = (ROOT / "raw" / "original" / member["path"]).read_bytes()
                self.assertEqual(content, archive.read(member["path"]))
                self.assertEqual(hashlib.sha256(content).hexdigest(), member["sha256"])
            actual_files = {p.relative_to(ROOT / "raw" / "original").as_posix()
                            for p in (ROOT / "raw" / "original").rglob("*") if p.is_file()}
            self.assertEqual(actual_files, {m["path"] for m in files})

    def test_regeneration_is_exact_and_cannot_write_raw(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            normalizer.build(target)
            self.assertEqual({p.name for p in target.iterdir()},
                             {p.name for p in (ROOT / "normalized").iterdir()})
            for path in target.iterdir():
                self.assertEqual(path.read_bytes(), (ROOT / "normalized" / path.name).read_bytes())
        with self.assertRaises(ValueError):
            normalizer.build(ROOT / "raw" / "forbidden")
        self.assertFalse((ROOT / "raw" / "forbidden").exists())

    def test_source_hashes_and_log_links(self):
        log = read_csv(normalizer.RAW / "_meta" / "fetch_log.csv")
        for loc, fixture in self.fixtures.items():
            sections = [fixture["soil_context"], fixture["weather_outlook"],
                        *fixture["vegetation_context"]["series"].values()]
            for section in sections:
                path = ROOT / section["source"]["path"]
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), section["source"]["sha256"])
                self.assertIn(loc, path.name)
                self.assertFalse(section["integration_ready"])
                for record in section["records"]:
                    self.assertGreaterEqual(record["source_csv_row"], 2)
                for row_number in section.get("candidate_fetch_log_rows", []):
                    self.assertEqual(log[row_number - 2]["outcome"], "ok")
                    self.assertIn(section["band"], log[row_number - 2]["url"])
            for record in fixture["soil_context"]["records"]:
                self.assertTrue(record["candidate_fetch_log_rows"])
                for row_number in record["candidate_fetch_log_rows"]:
                    candidate = log[row_number - 2]
                    self.assertEqual(candidate["target"], f"soilgrids_{loc}.csv")
                    self.assertIn(record["property"] + "_", candidate["url"])

    def test_soil_conversion_examples_and_unknown_uncertainty(self):
        soil = self.fixtures["hlegu"]["soil_context"]
        topsoil = {r["property"]: r for r in soil["records"] if r["depth_cm"]["top"] == 0}
        for prop, value in {"phh2o": 6.3, "clay": 33.4, "nitrogen": 2.74, "bdod": 1.26, "cec": 276.0}.items():
            self.assertAlmostEqual(topsoil[prop]["normalized"]["value"], value)
        # Rounded independent texture estimates are preserved, not forced to 100.
        self.assertAlmostEqual(sum(topsoil[p]["normalized"]["value"] for p in ("sand", "silt", "clay")), 100.1)
        for fixture in self.fixtures.values():
            context = fixture["soil_context"]
            self.assertEqual(len(context["records"]), 32)
            self.assertEqual(context["data_type"], "modeled")
            self.assertIsNone(context["drainage"]["value"])
            self.assertEqual(context["drainage"]["data_type"], "unavailable")
            for record in context["records"]:
                self.assertIsNone(record["prediction_interval_90"])
                self.assertEqual(record["data_type"], "modeled")

    def test_modis_missing_values_and_qa_are_not_promoted(self):
        expected_missing = {"hlegu": (41, 40), "bago": (39, 39), "magway": (15, 32)}
        for loc, fixture in self.fixtures.items():
            series = fixture["vegetation_context"]["series"]
            for label, expected in zip(("lst_day", "lst_night"), expected_missing[loc]):
                records = series[label]["records"]
                self.assertEqual(len(records), 92)
                self.assertEqual(sum(r["normalized_value"] is None for r in records), expected)
                for record in records:
                    self.assertIsNone(record["quality_flags"])
                    self.assertFalse(record["usable_for_analysis"])
                    if record["normalized_value"] is None:
                        self.assertEqual(record["data_type"], "unavailable")
                    else:
                        self.assertAlmostEqual(record["original_value"] * 0.02 - 273.15,
                                               record["normalized_value"])
                        self.assertEqual(record["data_type"], "observed")
            for label in ("ndvi", "evi"):
                self.assertEqual(len(series[label]["records"]), 46)
                self.assertEqual(series[label]["time_coverage"]["missing_composite_starts"], [])
                self.assertTrue(all(not r["usable_for_analysis"] for r in series[label]["records"]))

    def test_forecast_tail_gaps_zeroes_and_metadata(self):
        for fixture in self.fixtures.values():
            outlook = fixture["weather_outlook"]
            self.assertEqual(outlook["data_type"], "forecast")
            self.assertEqual(outlook["freshness_status"], "unverifiable_do_not_serve_as_live")
            for key in ("issue_at", "retrieved_at", "expires_at", "resolved_models"):
                self.assertIsNone(outlook[key])
            self.assertEqual(len(outlook["records"]), 16)
            for record in outlook["records"][-2:]:
                for key in ("sm_0_7_m3m3", "sm_7_28_m3m3", "soil_temp_0_7_c"):
                    self.assertIsNone(record["variables"][key]["value"])
                    self.assertEqual(record["variables"][key]["data_type"], "unavailable")
            zeroes = [r["variables"]["precip_mm"] for r in outlook["records"]
                      if r["variables"]["precip_mm"]["value"] == 0]
            self.assertTrue(zeroes)
            self.assertTrue(all(v["data_type"] == "forecast" for v in zeroes))

    def test_known_log_and_climatology_defects_remain_visible(self):
        log = read_csv(normalizer.RAW / "_meta" / "fetch_log.csv")
        self.assertEqual(len(log), 522)
        self.assertEqual(sum(r["outcome"] == "failed" for r in log), 81)
        self.assertFalse(any("POWER" in r["source"] or "forecast" in r["source"] for r in log))
        for loc in self.fixtures:
            rows = read_csv(normalizer.RAW / "csv" / f"power_climatology_{loc}.csv")
            self.assertEqual({r["month_name"] for r in rows if r["month"] == "1"}, {"FEB"})
            self.assertEqual({r["month_name"] for r in rows if r["month"] == "12"}, {"ANN"})

    def test_nonfinite_values_are_rejected_and_blanks_remain_unknown(self):
        for value in ("nan", "inf", "-inf"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                normalizer.number(value)
        self.assertIsNone(normalizer.number(""))
        self.assertEqual(normalizer.number("0"), 0)

    def test_unit_or_scale_drift_fails_before_normalization(self):
        soil_rows = read_csv(normalizer.RAW / "csv" / "soilgrids_hlegu.csv")
        soil_rows[0]["unit"] = "pH"
        with patch.object(normalizer, "read_csv", return_value=soil_rows):
            with self.assertRaisesRegex(ValueError, "unit"):
                normalizer.soil_fixture("hlegu", [])
        for field, value in (("scale", "1"), ("source_unit", "Kelvin")):
            modis_rows = read_csv(normalizer.RAW / "csv" / "modis_ndvi_hlegu.csv")
            modis_rows[0][field] = value
            with self.subTest(field=field), patch.object(normalizer, "read_csv", return_value=modis_rows):
                with self.assertRaisesRegex(ValueError, "scale or unit"):
                    normalizer.vegetation_fixture("hlegu", [])


if __name__ == "__main__":
    unittest.main()
