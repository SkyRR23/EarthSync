"""Required integration tests against the real, unchanged v0.3 Rust executable."""

from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from knowledge import ROOT, load, read_json

REPO = ROOT.parents[2]
BIN = Path(
    os.environ.get("EARTHSYNC_V03_BIN", REPO / "engine/target/debug/examples/v03_demo")
)


def analyze(request):
    result = subprocess.run(
        [str(BIN), "--stdin"],
        input=json.dumps(request),
        capture_output=True,
        text=True,
        check=True,
        timeout=20,
    )
    return json.loads(result.stdout)


class RustContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not BIN.is_file():
            raise RuntimeError(
                "Build engine example v03_demo first; this required integration suite does not silently skip"
            )
        load()

    def test_all_ten_requests_accepted_by_native_rust(self):
        fixtures = list((ROOT / "fixtures").glob("*.request.json"))
        self.assertEqual(len(fixtures), 10)
        for file in fixtures:
            with self.subTest(fixture=file.name):
                request = read_json(file)
                response = analyze(request)
                self.assertEqual(response["status"], "success", response)
                data = response["data"]
                self.assertTrue(data["software_test_only"])
                self.assertEqual(data["context"]["scenarios"], request["scenarios"])
                self.assertEqual(data["candidates"], [])
                self.assertTrue(
                    all(
                        s["status"] == "insufficient_information"
                        for s in data["summaries"]
                    )
                )
                self.assertTrue(
                    all(
                        f["status"] == "insufficient_information"
                        for f in data["findings"]
                        if f["rule_id"].startswith("catalog.")
                    )
                )

    def test_known_calendar_gap_and_overlap(self):
        for name, expected in [
            ("rice-mung", "supported_by_supplied_evidence"),
            ("declared-overlap", "conflicts_with_supplied_evidence"),
            ("declared-reverse-order", "conflicts_with_supplied_evidence"),
        ]:
            with self.subTest(fixture=name):
                request = read_json(ROOT / f"fixtures/{name}.request.json")
                data = analyze(request)["data"]
                findings = [
                    f for f in data["findings"] if f["rule_id"] == "schedule.sequential"
                ]
                self.assertEqual([f["status"] for f in findings], [expected])
                self.assertEqual(
                    data["context"]["scenarios"][0]["plans"],
                    request["scenarios"][0]["plans"],
                )

    def test_sidecar_is_not_an_engine_input(self):
        request = read_json(ROOT / "fixtures/rice-mung.request.json")
        request["catalog"][0]["recommendation_eligible"] = False
        self.assertEqual(analyze(request)["status"], "error")

    def test_fallow_remains_explicit_dated_history(self):
        request = read_json(ROOT / "fixtures/wheat-sorghum-fallow.request.json")
        data = analyze(request)["data"]
        self.assertEqual(data["context"]["history"], request["history"])
        self.assertTrue(data["context"]["history"][0]["fallow"])
        self.assertFalse(data["context"]["history_complete"])
        self.assertEqual(
            data["context"]["history"][0]["provenance"]["kind"], "synthetic"
        )

    def test_real_mode_does_not_promote_reference_catalog(self):
        request = deepcopy(read_json(ROOT / "fixtures/rice-mung.request.json"))
        request["mode"] = "evidence_assessment"
        request["sources"], request["history"] = [], []
        request["farm"] = None
        response = analyze(request)
        self.assertEqual(response["status"], "success")
        self.assertEqual(response["data"]["candidates"], [])
        self.assertTrue(
            all(
                f["status"] == "insufficient_information"
                for f in response["data"]["findings"]
            )
        )


if __name__ == "__main__":
    unittest.main()
