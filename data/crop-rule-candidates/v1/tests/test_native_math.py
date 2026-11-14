"""Real unchanged Rust arithmetic with synthetic daily ETo; no agricultural approval."""

from copy import deepcopy
from datetime import date, timedelta
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from method_checks import example28_kc
from package import REPO, read

BIN = Path(
    os.environ.get("EARTHSYNC_V03_BIN", REPO / "engine/target/debug/examples/v03_demo")
)


def day(value):
    return {"year": value.year, "month": value.month, "day": value.day}


def request():
    data = read(REPO / "engine/tests/fixtures/v03/synthetic_request.json")
    period = {"start": day(date(2025, 1, 1)), "end": day(date(2025, 4, 10))}
    data["scenarios"][0]["plans"][0]["period"] = period
    data["observations"], data["history"], data["photos"] = [], [], []
    data["history_complete"] = False
    data["candidate_window"] = None
    profile = data["catalog"][0]
    rule = next(r for r in profile["rules"] if r["id"] == "test.etc")
    rule["requirement"]["stages"] = [
        {
            "id": f"synthetic-day-{i}",
            "first_day": i,
            "last_day": i,
            "kc": float(example28_kc(i)),
        }
        for i in range(1, 101)
    ]
    profile["rules"] = [rule]
    profile["approved_for_candidates"] = False
    data["catalog"] = [profile]
    et0 = deepcopy(next(s for s in data["climate"] if s["variable"] == "et0"))
    et0["provenance"]["period"] = period
    et0["provenance"]["retrieved_on"] = day(date(2025, 4, 11))
    et0["days"] = [
        {
            "date": day(date(2025, 1, 1) + timedelta(days=i)),
            "value": 5,
            "quality": "usable",
        }
        for i in range(100)
    ]
    data["climate"] = [et0]
    return data


def analyze(data):
    result = subprocess.run(
        [str(BIN), "--stdin"],
        input=json.dumps(data),
        text=True,
        capture_output=True,
        check=True,
        timeout=20,
    )
    result = json.loads(result.stdout)
    if result["status"] != "success":
        raise AssertionError(result)
    return result["data"]


class NativeMethodContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not BIN.is_file():
            raise RuntimeError(
                "Build v03_demo first; required native checks never silently skip"
            )

    def test_daily_curve_encoding_matches_closed_form_synthetic_etc(self):
        result = analyze(request())
        finding = next(f for f in result["findings"] if f["rule_id"] == "test.etc")
        self.assertAlmostEqual(finding["input"]["total_etc_mm"], 358.50, places=9)
        self.assertTrue(result["software_test_only"])
        self.assertEqual(result["candidates"], [])

    def test_missing_daily_et0_does_not_become_zero(self):
        data = request()
        data["climate"][0]["days"][49]["value"] = None
        data["climate"][0]["days"][49]["quality"] = "missing"
        result = analyze(data)
        finding = next(f for f in result["findings"] if f["rule_id"] == "test.etc")
        self.assertEqual(finding["status"], "insufficient_information")
        self.assertNotIn("total_etc_mm", finding["input"])

    def test_four_constant_stages_do_not_reproduce_published_curve(self):
        data = request()
        data["catalog"][0]["rules"][0]["requirement"]["stages"] = [
            {"id": name, "first_day": first, "last_day": last, "kc": kc}
            for name, first, last, kc in [
                ("initial", 1, 25, 0.15),
                ("development", 26, 50, 1.19),
                ("mid", 51, 80, 1.19),
                ("late", 81, 100, 0.35),
            ]
        ]
        result = analyze(data)
        finding = next(f for f in result["findings"] if f["rule_id"] == "test.etc")
        self.assertAlmostEqual(finding["input"]["total_etc_mm"], 381.0, places=9)
        self.assertNotAlmostEqual(finding["input"]["total_etc_mm"], 358.50, places=9)


if __name__ == "__main__":
    unittest.main()
