"""Deterministic data/software checks; no provider access or agronomic acceptance."""

from copy import deepcopy
import csv
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from jsonschema import ValidationError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from build import generate
from capture import fetch
from importers import (
    COLUMNS,
    agricultural_categories,
    bounds,
    calendar_sessions,
    calendar_window,
    ecocrop_csv,
    ecocrop_sheet,
    grin_identity,
    soil_value,
)
from knowledge import (
    ROOT,
    index,
    load,
    lookup,
    project,
    read_json,
    validate,
    verify_integrity,
)
from reference_products import gaez_reference


class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = load()

    def mutated(self, edit):
        data = deepcopy(self.data)
        edit(data)
        with self.assertRaises((ValueError, ValidationError)):
            validate(data)

    def test_source_identity_matches_receipt(self):
        self.mutated(
            lambda d: d["sources"][0].update(url="https://example.invalid/wrong-source")
        )

    def test_version_is_pinned(self):
        self.mutated(lambda d: d["sources"][0].update(version="latest"))

    def test_publication_date_precision_is_preserved(self):
        self.mutated(
            lambda d: d["sources"][0].update(
                publication_date="2021-02-30", publication_date_precision="day"
            )
        )
        self.mutated(
            lambda d: d["sources"][0].update(
                publication_date="2021", publication_date_precision="unknown"
            )
        )

    def test_mandatory_inventory_is_typed_and_sources_resolve(self):
        from jsonschema import Draft202012Validator

        inventory = read_json(ROOT / "dataset-inventory.json")
        Draft202012Validator(
            read_json(ROOT / "dataset-inventory.schema.json")
        ).validate(inventory)
        self.assertEqual(
            {d["id"] for d in inventory},
            {"ecocrop", "gaez_v5", "crop_calendar", "soilgrids", "grin"},
        )
        sources = index(self.data["sources"])
        self.assertTrue(all(s in sources for d in inventory for s in d["source_ids"]))

    def test_nasa_inventory_never_claims_new_numeric_access(self):
        inventory = read_json(ROOT / "nasa-compatibility.json")
        self.assertEqual(
            {d["id"] for d in inventory},
            {"power", "imerg", "smap", "modis", "hls", "opera", "gibs", "cmr"},
        )
        self.assertTrue(all(d["numerical_claim_added"] is False for d in inventory))
        self.assertEqual(
            next(d for d in inventory if d["id"] == "gibs")["evidence_class"], 2
        )

    def test_source_review_cannot_be_promoted(self):
        self.mutated(lambda d: d["sources"][0].update(review="reviewed"))

    def test_unavailable_source_cannot_support_claim(self):
        self.mutated(
            lambda d: index(d["sources"])[d["claims"][0]["source_id"]].update(
                access_status="unavailable"
            )
        )

    def test_invalid_source_scheme_rejected(self):
        self.mutated(lambda d: d["sources"][0].update(url="javascript:invalid"))

    def test_dangling_claim_source_rejected(self):
        self.mutated(lambda d: d["claims"][0].update(source_id="missing-source"))

    def test_invalid_supporting_source_rejected(self):
        self.mutated(lambda d: d["claims"][0].update(supporting_source_ids=["missing"]))

    def test_crop_ids_are_versioned_and_unique(self):
        self.assertEqual(len(index(self.data["crops"])), 708)
        self.assertTrue(
            all(
                c["id"].startswith("ecocrop.") and c["id"].endswith("@1")
                for c in self.data["crops"]
            )
        )

    def test_duplicate_crop_id_rejected(self):
        self.mutated(lambda d: d["crops"].append(deepcopy(d["crops"][0])))

    def test_crop_identity_drift_rejected(self):
        self.mutated(lambda d: d["crops"][0].update(scientific_name="Unknown species"))

    def test_cultivated_agricultural_filter(self):
        self.assertEqual(
            agricultural_categories(
                {"PLAT": "harvested from wild", "CAT": "vegetables"}
            ),
            [],
        )
        self.assertEqual(
            agricultural_categories(
                {"PLAT": "grown on small scale", "CAT": "ornamentals/turf, materials"}
            ),
            [],
        )
        self.assertEqual(
            agricultural_categories({"PLAT": "", "CAT": "forage/pasture"}), []
        )
        self.assertEqual(
            agricultural_categories(
                {"PLAT": "grown on small scale", "CAT": "forage/pasture"}
            ),
            ["forage_fodder"],
        )

    def test_full_species_enumeration_is_not_crop_promotion(self):
        inventory = [
            json.loads(line)
            for line in (ROOT / "species-inventory.jsonl").read_text().splitlines()
        ]
        self.assertEqual(len(inventory), 2568)
        self.assertEqual(
            len({x["scientific_name_as_published"] for x in inventory}), 2568
        )
        self.assertGreater(
            sum(x["agricultural_catalog_id"] is None for x in inventory), 1800
        )
        self.assertTrue(
            all(
                c["profile_coverage"] == "identity_only"
                for c in self.data["crops"]
                if c["id"] not in {p["crop_id"] for p in self.data["profiles"]}
            )
        )

    def test_priority_aliases_resolve(self):
        for query in [
            "RICE",
            "mung bean",
            "green gram",
            "sesame",
            "peanut",
            "groundnut",
            "maize",
        ]:
            with self.subTest(query=query):
                self.assertEqual(lookup(self.data, query)["status"], "reference_only")
        self.assertEqual(lookup(self.data, "corn")["status"], "ambiguous")

    def test_alias_collision_is_ambiguous(self):
        data = deepcopy(self.data)
        data["crops"][0]["aliases"].append("collision")
        data["crops"][1]["aliases"].append("collision")
        self.assertEqual(lookup(data, "collision")["status"], "ambiguous")
        self.assertEqual(lookup(data, "collision")["profiles"], [])

    def test_no_fuzzy_taxon_fallback(self):
        self.assertEqual(lookup(self.data, "Oryza")["status"], "unavailable")

    def test_region_scope_has_no_nearest_fallback(self):
        self.assertEqual(lookup(self.data, "rice", region="MM-unknown")["profiles"], [])

    def test_cultivar_has_no_generic_fallback(self):
        self.assertEqual(
            lookup(self.data, "groundnut", cultivar="invented-variety")["profiles"], []
        )

    def test_production_system_has_no_fallback(self):
        self.assertEqual(
            lookup(self.data, "rice", system="unknown-system")["profiles"], []
        )

    def test_unknowns_stay_null_with_reason(self):
        for p in self.data["profiles"]:
            for value in p["parameters"].values():
                if value["state"] == "unknown":
                    self.assertIsNone(value["value"])
                    self.assertTrue(value["missing_reason"])
        self.mutated(
            lambda d: d["profiles"][0]["parameters"]["growing_period_rainfall"].update(
                value=0
            )
        )

    def test_populated_parameter_requires_claim(self):
        self.mutated(
            lambda d: d["profiles"][0]["parameters"]["annual_precipitation"].update(
                claim_ids=[]
            )
        )

    def test_units_must_match_claim(self):
        self.mutated(
            lambda d: d["profiles"][0]["parameters"]["annual_precipitation"].update(
                unit="mm_per_day"
            )
        )

    def test_parameter_cannot_relabel_statistic(self):
        self.mutated(
            lambda d: d["profiles"][0]["parameters"]["ecological_temperature"].update(
                statistic="daily Tmin/Tmax"
            )
        )

    def test_nonfinite_numbers_rejected(self):
        self.mutated(
            lambda d: d["profiles"][0]["parameters"]["ecological_temperature"]["value"][
                "absolute"
            ].update(min=float("nan"))
        )

    def test_reversed_bounds_rejected(self):
        self.mutated(
            lambda d: d["profiles"][0]["parameters"]["ecological_temperature"]["value"][
                "absolute"
            ].update(min=1000)
        )

    def test_global_ecology_cannot_become_regional(self):
        self.mutated(lambda d: d["profiles"][0].update(region_id="MM-FAO-AEZ-001"))

    def test_claim_cultivar_must_match(self):
        self.mutated(
            lambda d: index(d["profiles"])["groundnut.mm.erect-type@1"].update(
                cultivar="other"
            )
        )

    def test_claim_region_must_match(self):
        self.mutated(
            lambda d: next(
                p for p in d["profiles"] if ".mm.calendar-" in p["id"]
            ).update(region_id="other")
        )

    def test_claim_system_must_match(self):
        self.mutated(
            lambda d: next(
                p for p in d["profiles"] if ".mm.calendar-" in p["id"]
            ).update(production_system="other")
        )

    def test_new_profiles_cannot_be_promoted(self):
        for field, value in [
            ("recommendation_eligible", True),
            ("approved_for_candidates", True),
            ("review", "reviewed"),
            ("executable_rules", [{"id": "invented"}]),
        ]:
            with self.subTest(field=field):
                self.mutated(lambda d: d["profiles"][0].update({field: value}))

    def test_rotation_input_order_cannot_be_sorted_to_pass(self):
        self.mutated(lambda d: d["rotations"][0]["cycles"].reverse())

    def test_rotation_overlap_rejected(self):
        self.mutated(
            lambda d: d["rotations"][0]["cycles"][1].update(start="2024-08-31")
        )

    def test_fallow_is_not_a_crop(self):
        self.mutated(
            lambda d: d["rotations"][-1]["cycles"][-1].update(
                crop_id=d["crops"][0]["id"]
            )
        )

    def test_offline_loading_needs_no_network(self):
        with patch(
            "urllib.request.urlopen", side_effect=AssertionError("network forbidden")
        ):
            self.assertEqual(lookup(load(), "sesame")["status"], "reference_only")

    def test_generated_artifacts_reproduce(self):
        for name, content in generate().items():
            self.assertEqual((ROOT / name).read_bytes(), content, name)

    def test_original_hash_damage_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "pack"
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns("__pycache__"))
            with (root / "originals/ecocrop_rice.html").open("ab") as output:
                output.write(b"damage")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                verify_integrity(root)
            with self.assertRaisesRegex(
                ValueError, "original provider/mirror bytes changed"
            ):
                generate(root)

    def test_duplicate_and_nonfinite_json_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "provider.json"
            for text in ['{"a":1,"a":2}', '{"a":NaN}']:
                file.write_text(text)
                with self.assertRaises(ValueError):
                    read_json(file)


class ImporterTests(unittest.TestCase):
    def test_official_sheet_species_identity(self):
        raw = (ROOT / "originals/ecocrop_rice.html").read_bytes()
        self.assertEqual(
            ecocrop_sheet(raw, "Oryza sativa")["annual_precipitation"]["optimal"][
                "min"
            ],
            1500,
        )
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            ecocrop_sheet(raw, "Vigna radiata")

    def test_error_or_truncated_html_not_accepted(self):
        for raw in [b"<html>Service not found</html>", b"<h2>Oryza sativa</h2><table>"]:
            with self.assertRaises(ValueError):
                ecocrop_sheet(raw, "Oryza sativa")

    def test_grin_rejects_wrong_species_and_family(self):
        raw = b'<h1 class="title">Taxon:&nbsp; <i>Oryzopsis miliacea</i> L.</h1>Family: Poaceae'
        with self.assertRaises(ValueError):
            grin_identity(raw, "Oryza sativa", "Poaceae")
        good = b'<h1 class="title">Taxon:&nbsp; <i>Vigna radiata</i> (L.) R. Wilczek</h1>Family: Fabaceae'
        self.assertEqual(
            grin_identity(good, "Vigna radiata", "Fabaceae")["scientific_name"],
            "Vigna radiata",
        )
        with self.assertRaises(ValueError):
            grin_identity(good, "Vigna radiata", "Poaceae")

    def test_gaez_metadata_identity_license_and_missing_science(self):
        raw = (ROOT / "originals/gaez_v5_metadata.json").read_bytes()
        result = gaez_reference(raw)
        self.assertIsNone(result["numerical_extract"])
        self.assertFalse(result["usable_for_assessment"])
        for field, wrong in [("name", "gaez-v4"), ("license_id", "unspecified")]:
            document = json.loads(raw)
            document["result"][field] = wrong
            with self.assertRaises(ValueError):
                gaez_reference(json.dumps(document))
        with self.assertRaises(ValueError):
            gaez_reference('{"success":false}')

    def test_rejected_live_soil_capture_is_not_available_evidence(self):
        receipt = read_json(ROOT / "evidence/soil-wcs-rejected-receipt.json")
        self.assertEqual(receipt["reason"], "SOIL_ENCODING_MISMATCH")
        self.assertIsNone(receipt["diagnostic_only"]["nodata"])
        self.assertFalse(receipt["usable_for_assessment"])

    def test_provider_csv_missing_schema_or_truncation(self):
        raw = (ROOT / "originals/ecocrop_openclim_ea43ecd.csv").read_bytes()
        for bad, count in [(b"fake,header\n1,2\n", 1), (raw[:-100], 2568), (raw, 2567)]:
            with self.assertRaises(ValueError):
                ecocrop_csv(bad, count)

    def test_duplicate_csv_identity_rejected(self):
        buffer = io.StringIO()
        writer = csv.DictWriter(buffer, COLUMNS)
        writer.writeheader()
        row = dict.fromkeys(COLUMNS, "")
        row.update(EcoPortCode="1", ScientificName="Test species")
        writer.writerows([row, row])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            ecocrop_csv(buffer.getvalue().encode(), 2)

    def test_soil_scales_preserve_native_value_depth_and_statistic(self):
        for property, raw, expected in [
            ("phh2o", 65, 6.5),
            ("soc", 150, 15),
            ("bdod", 130, 1.3),
            ("clay", 250, 25),
            ("sand", 600, 60),
            ("silt", 150, 15),
            ("cfvo", 100, 10),
            ("nitrogen", 200, 2),
        ]:
            with self.subTest(property=property):
                value = soil_value(property, raw, 5, 15, "Q05")
                self.assertEqual(value["value"], expected)
                self.assertEqual(value["original_value"], raw)
                self.assertEqual(value["depth_cm"], {"top": 5, "bottom": 15})
                self.assertEqual(value["statistic"], "Q05")
                self.assertFalse(value["usable_for_assessment"])

    def test_soil_missing_is_not_zero(self):
        for raw in [None, -32768]:
            result = soil_value("phh2o", raw, 0, 5, "mean", nodata=-32768)
            self.assertIsNone(result["value"])
            self.assertEqual(result["quality"], "missing")

    def test_soil_depth_and_quantile_cannot_be_substituted(self):
        for args in [
            ("phh2o", 65, 0, 15, "mean"),
            ("phh2o", 65, 0, 5, "Q99"),
            ("phh2o", float("inf"), 0, 5, "mean"),
        ]:
            with self.assertRaises(ValueError):
                soil_value(*args)

    def test_calendar_wrap_and_invalid_dates(self):
        self.assertTrue(
            calendar_window({"month": "11", "day": "1"}, {"month": "2", "day": "28"})[
                "wraps_year"
            ]
        )
        with self.assertRaises(ValueError):
            calendar_window({"month": "0", "day": "1"}, {"month": "2", "day": "28"})

    def test_calendar_wrong_country_and_malformed_duration(self):
        with self.assertRaises(ValueError):
            calendar_sessions([{"id_country": "OTHER"}])
        with self.assertRaises(ValueError):
            calendar_sessions({"error": "not a dataset"})
        record = {
            "id_country": "MM",
            "lastUpdated": "26/02/2021",
            "crop": {"id": "0303", "name": "Rice"},
            "sessions": [{"growing_period": {"period": "months", "value": "3"}}],
        }
        with self.assertRaisesRegex(ValueError, "duration"):
            calendar_sessions([record])

    def test_missing_and_ordered_source_bounds(self):
        self.assertEqual(bounds("-", "2500"), {"min": None, "max": 2500})
        with self.assertRaises(ValueError):
            bounds("20", "10")

    def test_truncated_empty_and_oversized_downloads(self):
        class Response(io.BytesIO):
            status = 200
            headers = {"Content-Length": "20"}

            def geturl(self):
                return "https://example.invalid/test"

        for body, limit in [(b"short", 100), (b"", 100), (b"twenty bytes exactly!", 5)]:
            with self.assertRaises(ValueError):
                fetch(
                    "https://example.invalid/test",
                    limit,
                    opener=lambda *a, **k: Response(body),
                )

    def test_identity_only_projection_preserves_sidecar(self):
        data = load()
        p = index(data["profiles"])["rice.mm.calendar-5-sessions-0@1"]
        result = project(data, p["id"], p["region_id"], p["production_system"])
        self.assertEqual(result["profile"]["rules"], [])
        self.assertEqual(result["profile"]["review"], "reference_only")
        self.assertFalse(result["profile"]["approved_for_candidates"])
        self.assertTrue(result["sidecar"]["claims"])
        self.assertTrue(result["sidecar"]["sources"])

    def test_mapping_rejects_wrong_context_and_ambiguous_system(self):
        data = load()
        p = index(data["profiles"])["rice.mm.calendar-5-sessions-0@1"]
        for region, system, cultivar in [
            ("OTHER", p["production_system"], None),
            (p["region_id"], "flooded_irrigated_lowland", None),
            (p["region_id"], p["production_system"], "other"),
        ]:
            with self.assertRaises(ValueError):
                project(data, p["id"], region, system, cultivar)
        with self.assertRaises(ValueError):
            project(
                data,
                "rice.au.drill-delayed-flood@1",
                "AU-NSW-Riverina",
                "irrigated_drill_sown_delayed_flood",
            )


if __name__ == "__main__":
    unittest.main()
