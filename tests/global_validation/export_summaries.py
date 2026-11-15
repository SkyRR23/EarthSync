"""Export allowlisted public-site forecast metadata, never farm/runtime identities."""

import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def export(private):
    manifest = json.loads((ROOT / "tests/global_validation/sites.json").read_text())
    allowed = {s["id"] for s in manifest["sites"]}
    rows = []
    for ident in ["mm_delta", "us_mead"]:
        assert ident in allowed
        result = json.loads((private / "runtime" / ident / "forecast.json").read_text())
        for record in result["records"]:
            assert (
                abs(record["raw_temperature_k"] - 273.15 - record["temperature_c"])
                < 1e-8
            )
            rows.append(
                {
                    "site_id": ident,
                    "release_sha": manifest["release_sha"],
                    **{
                        k: record[k]
                        for k in [
                            "source_url",
                            "source_sha256",
                            "retrieved_at",
                            "valid_at",
                            "forecast_hour",
                            "model_initialized_at",
                            "native_unit",
                            "raw_temperature_k",
                            "temperature_c",
                            "unit",
                            "quality",
                        ]
                    },
                    "issued_at": result["issued_at"],
                    "grid_spacing_degrees": result["grid_spacing_degrees"],
                    "classification": "CACHED REAL source record; not station observation or new forecast retrieval",
                    "note": "lead zero is model initialization/analysis, not an observed weather report; later matching observations unavailable",
                }
            )
    (ROOT / "docs/validation/evidence/forecast-records.json").write_text(
        json.dumps(rows, indent=2) + "\n"
    )
    spec = importlib.util.spec_from_file_location(
        "baseline_integrity", ROOT / "scripts/verify_7x_integrity.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    (ROOT / "docs/validation/evidence/scientific-integrity.json").write_text(
        json.dumps(module.verify(ROOT), indent=2) + "\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--private", type=Path, required=True)
    export(parser.parse_args().private)
