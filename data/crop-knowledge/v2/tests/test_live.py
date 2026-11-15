"""Explicit live source retrieval; run separately, never count a skipped provider as passed."""

import json
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from capture import fetch
from importers import ecocrop_sheet, calendar_sessions


class LiveSources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("EARTHSYNC_LIVE") != "1":
            raise RuntimeError(
                "Live suite requires explicit EARTHSYNC_LIVE=1; not skipped/passed by the offline suite"
            )

    def test_official_ecocrop_sheet(self):
        raw, _, _, _ = fetch(
            "https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=2150", 100000
        )
        self.assertEqual(
            ecocrop_sheet(raw, "Vigna radiata")["ecological_crop_cycle"],
            {"min": 50, "max": 120},
        )

    def test_myanmar_calendar_presence_and_regions(self):
        raw, _, _, _ = fetch(
            "https://api-cropcalendar.apps.fao.org/api/v1/countries/MM/cropCalendar?language=en",
            2000000,
        )
        sessions = calendar_sessions(
            json.loads(raw), {"0303", "0157", "0232", "0262", "0318", "0113"}
        )
        self.assertEqual(len(sessions), 55)
        self.assertTrue(any(s["season"] == "Summer Rice" for s in sessions))
        self.assertTrue(any(s["comments"] == "upland rice" for s in sessions))

    def test_official_ecocrop_license(self):
        raw, _, _, _ = fetch(
            "https://data.fao.org/catalog/api/3/action/package_show?id=ecocrop", 100000
        )
        self.assertEqual(json.loads(raw)["result"]["license_id"], "CC-BY-4.0")

    def test_cmr_discovery_is_metadata_not_pixels(self):
        raw, _, _, _ = fetch(
            "https://cmr.earthdata.nasa.gov/search/collections.json?short_name=HLSL30&version=2.0&page_size=1",
            200000,
        )
        entries = json.loads(raw)["feed"]["entry"]
        self.assertTrue(entries)
        self.assertEqual(entries[0]["short_name"], "HLSL30")


if __name__ == "__main__":
    unittest.main()
