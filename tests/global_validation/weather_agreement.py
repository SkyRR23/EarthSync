"""Descriptive station agreement, not held-out global accuracy validation.

Uses existing production daily outputs. Additional hourly POWER responses only
audit UTC↔LST timestamp alignment; they never replace production climate values.
"""

import asyncio
import csv
import hashlib
import io
import json
from pathlib import Path
from datetime import datetime, timedelta, timezone
import httpx
from reference import metrics

ROOT = Path(__file__).resolve().parents[2]


def station_rows(raw):
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    if not {"STATION", "DATE", "TMP"} <= set(reader.fieldnames or []):
        raise ValueError("Rejected non-station CSV / HTTP-200 HTML")
    result = []
    for row in reader:
        try:
            value, quality = row["TMP"].split(",")
            if quality not in ["1", "5"] or abs(int(value)) == 9999:
                continue
            stamp = datetime.fromisoformat(row["DATE"]).replace(tzinfo=timezone.utc)
            result.append((stamp, int(value) / 10))
        except (KeyError, ValueError):
            continue
    return result


async def main(private):
    config = json.loads((ROOT / "tests/global_validation/protocol.json").read_text())
    sites = json.loads((ROOT / "tests/global_validation/sites.json").read_text())[
        "sites"
    ]
    rows = []
    audit = []
    async with httpx.AsyncClient(timeout=30) as client:
        for ident, station in [
            ("us_mead", "72094200323"),
            ("us_bondville", "72531594870"),
        ]:
            site = next(s for s in sites if s["id"] == ident)
            offset = round(site["longitude"] / 15)
            bodies = {}
            for standard in ["UTC", "LST"]:
                path = private / "references" / f"{ident}-hourly-{standard}.json"
                params = {
                    "parameters": "T2M",
                    "community": "AG",
                    "latitude": site["latitude"],
                    "longitude": site["longitude"],
                    "start": "20240101",
                    "end": "20240103",
                    "format": "JSON",
                    "time-standard": standard,
                }
                if not path.exists():
                    r = await client.get(
                        "https://power.larc.nasa.gov/api/temporal/hourly/point",
                        params=params,
                    )
                    r.raise_for_status()
                    path.write_bytes(r.content)
                body = path.read_bytes()
                data = json.loads(body)
                assert data["header"]["time_standard"] == standard
                bodies[standard] = data["properties"]["parameter"]["T2M"]
                audit.append(
                    {
                        "release_sha": config["release_sha"],
                        "site_id": ident,
                        "purpose": "time-boundary audit only",
                        "source": "NASA POWER hourly T2M",
                        "time_standard": standard,
                        "sha256": hashlib.sha256(body).hexdigest(),
                    }
                )
            matches = 0
            for stamp, value in bodies["LST"].items():
                utc = (
                    datetime.strptime(stamp, "%Y%m%d%H") - timedelta(hours=offset)
                ).strftime("%Y%m%d%H")
                if utc in bodies["UTC"]:
                    assert abs(value - bodies["UTC"][utc]) <= 1e-9
                    matches += 1
            assert matches >= 24
            observed = station_rows(
                (private / "references" / f"{station}-2024-aws.csv").read_bytes()
            )
            for period in config["periods"]:
                records = json.loads(
                    (private / "runtime" / ident / (period[0] + ".json")).read_text()
                )["production_result"]["records"]
                for variable in ["tmin", "tmax"]:
                    record = next(
                        r
                        for r in records
                        if r["measurements"][0]["variable"] == variable
                    )
                    pairs = []
                    hour_counts = []
                    for measurement in record["measurements"]:
                        day = datetime.fromisoformat(str(measurement["date"])).date()
                        values = [
                            (stamp, value)
                            for stamp, value in observed
                            if (stamp + timedelta(hours=offset)).date() == day
                        ]
                        hours = len({stamp.hour for stamp, _ in values})
                        hour_counts.append(hours)
                        if (
                            hours
                            >= config["metrics"]["minimum_valid_station_hours_per_day"]
                            and measurement["value"] is not None
                        ):
                            extrema = (min if variable == "tmin" else max)(
                                v for _, v in values
                            )
                            pairs.append((measurement["value"], extrema))
                    m = metrics(pairs)
                    rows.append(
                        {
                            "release_sha": config["release_sha"],
                            "site_id": ident,
                            "station_id": station,
                            "start": period[0],
                            "end": period[1],
                            "variable": variable,
                            "unit": "degrees C",
                            "n": m["n"],
                            "mae": m["mae"],
                            "rmse": m["rmse"],
                            "bias": m["bias"],
                            "matched_day_coverage": m["n"] / 7,
                            "min_accepted_hour_bins": min(hour_counts),
                            "time_standard": "verified POWER LST",
                            "utc_offset_hours": offset,
                            "hourly_alignment_pairs": matches,
                            "classification": "DESCRIPTIVE OBSERVATIONAL AGREEMENT; sample below predeclared 10-day per-stratum minimum; not independent held-out accuracy",
                            "limitations": "Station instantaneous report extrema vs regional hourly-derived model extrema; spatial/elevation/sampling mismatch; assimilation overlap unknown; no confidence interval or agricultural accuracy approval",
                        }
                    )
            # Pool the two preselected seasons only as an additional descriptive statistic.
            # Per-season results remain separate; no model pass/fail or global score.
    out = ROOT / "docs/validation"
    with (out / "WEATHER_VALIDATION.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    (out / "evidence/time-alignment-audit.json").write_text(
        json.dumps(audit, indent=2) + "\n"
    )
    print(
        json.dumps(
            {
                "strata": len(rows),
                "total_comparison_pairs": sum(r["n"] for r in rows),
                "status": "DESCRIPTIVE ONLY; no global or held-out accuracy conclusion",
            }
        )
    )


if __name__ == "__main__":
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("--private", type=Path, required=True)
    a = p.parse_args()
    asyncio.run(main(a.private))
