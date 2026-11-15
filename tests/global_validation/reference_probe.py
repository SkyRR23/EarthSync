"""Bounded reference-availability audit, separate from model-provider adapters.

NOAA station observations are never silently aligned to POWER solar days, and
unverified model-training independence never becomes held-out validation.
"""

import asyncio
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import math
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[2]


def distance(a, b, c, d):
    p, q = map(math.radians, [a, c])
    dx = math.radians(c - a)
    dy = math.radians(d - b)
    return (
        6371
        * 2
        * math.asin(
            math.sqrt(
                math.sin(dx / 2) ** 2
                + math.cos(p) * math.cos(q) * math.sin(dy / 2) ** 2
            )
        )
    )


async def main(private):
    PRIVATE = private / "references"
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    report = {
        "release_sha": "660b479c3ffb714cd1d489e1241c026ceae6ed67",
        "attempts": [],
        "stations": [],
    }
    async with httpx.AsyncClient(timeout=35, follow_redirects=True) as client:

        async def retrieve(url, name, limit=12000000):
            started = datetime.now(timezone.utc).isoformat()
            path = PRIVATE / name
            if path.exists():
                report["attempts"].append(
                    {
                        "url": url,
                        "status": "CACHED_HTTP_BODY",
                        "bytes": path.stat().st_size,
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "classification": "Content must still pass format/QA; not proof of observations",
                    }
                )
                return path.read_bytes()
            try:
                async with client.stream("GET", url) as r:
                    r.raise_for_status()
                    body = bytearray()
                    async for part in r.aiter_bytes():
                        body.extend(part)
                        if len(body) > limit:
                            raise ValueError("REFERENCE_BODY_LIMIT")
                path.write_bytes(body)
                report["attempts"].append(
                    {
                        "url": url,
                        "status": "OBTAINED",
                        "bytes": len(body),
                        "sha256": hashlib.sha256(body).hexdigest(),
                        "retrieved_at": started,
                    }
                )
                return bytes(body)
            except Exception as exc:
                report["attempts"].append(
                    {
                        "url": url,
                        "status": "UNAVAILABLE",
                        "error": type(exc).__name__,
                        "retrieved_at": started,
                    }
                )
                return None

        data = await retrieve(
            "https://www.ncei.noaa.gov/pub/data/noaa/isd-history.csv", "isd-history.csv"
        )
        if data:
            stations = list(csv.DictReader(io.StringIO(data.decode("utf-8-sig"))))
            for ident, lat, lon in [
                ("us_mead", 41.1651, -96.4766),
                ("us_bondville", 40.006, -88.290),
            ]:
                possible = []
                for s in stations:
                    try:
                        if (
                            s["CTRY"] == "US"
                            and s["BEGIN"] <= "20240101"
                            and s["END"] >= "20241231"
                        ):
                            possible.append(
                                (
                                    distance(
                                        lat, lon, float(s["LAT"]), float(s["LON"])
                                    ),
                                    s,
                                )
                            )
                    except (ValueError, KeyError):
                        pass
                if not possible:
                    continue
                km, station = min(possible, key=lambda x: x[0])
                code = station["USAF"] + station["WBAN"]
                row = {
                    "site_id": ident,
                    "station_id": code,
                    "name": station["STATION NAME"],
                    "latitude": station["LAT"],
                    "longitude": station["LON"],
                    "elevation_m": station["ELEV(M)"],
                    "distance_km": km,
                    "source": "NOAA ISD public station catalog",
                    "independence": "MERRA-2 assimilation overlap not established; not held-out validation",
                }
                raw = await retrieve(
                    f"https://www.ncei.noaa.gov/data/global-hourly/access/2024/{code}.csv",
                    code + "-2024.csv",
                )
                if raw:
                    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
                    if not {"STATION", "DATE", "TMP"} <= set(reader.fieldnames or []):
                        row["initial_ncei_body_rejected"] = True
                        raw = await retrieve(
                            f"https://noaa-global-hourly-pds.s3.amazonaws.com/2024/{code}.csv",
                            code + "-2024-aws.csv",
                        )
                        if raw is None or not {"STATION", "DATE", "TMP"} <= set(
                            csv.DictReader(
                                io.StringIO(raw.decode("utf-8-sig"))
                            ).fieldnames
                            or []
                        ):
                            row["comparison_status"] = (
                                "UNAVAILABLE: rejected HTTP-200 HTML / non-station CSV"
                            )
                            row["observation_rows"] = 0
                            report["stations"].append(row)
                            continue
                        row["observation_source"] = (
                            f"https://noaa-global-hourly-pds.s3.amazonaws.com/2024/{code}.csv"
                        )
                    count = 0
                    valid = 0
                    dates = []
                    for observation in csv.DictReader(
                        io.StringIO(raw.decode("utf-8-sig"))
                    ):
                        count += 1
                        try:
                            v, q = observation["TMP"].split(",")
                            if q in ["1", "5"] and v not in ["+9999", "9999"]:
                                float(v) / 10
                                valid += 1
                                dates.append(observation["DATE"])
                        except (KeyError, ValueError):
                            pass
                    row.update(
                        observation_rows=count,
                        accepted_temperature_rows=valid,
                        first=min(dates) if dates else None,
                        last=max(dates) if dates else None,
                        comparison_status="NOT MEASURED: hourly UTC source obtained; POWER LST aggregation and held-out independence not independently established",
                    )
                else:
                    row["comparison_status"] = (
                        "UNAVAILABLE: station annual observation download failed or exceeded bounded size"
                    )
                report["stations"].append(row)
        # Inspect actual documentation, without claiming possession of soil samples.
        await retrieve(
            "https://docs.isric.org/globaldata/wosis/", "wosis.html", 2000000
        )
        await retrieve(
            "https://power.larc.nasa.gov/docs/services/api/temporal/hourly/",
            "power-hourly.html",
            2000000,
        )
        await retrieve(
            "https://www.ncei.noaa.gov/products/land-based-station/integrated-surface-database",
            "isd-docs.html",
            2000000,
        )
    report["soil_validation"] = (
        "NOT MEASURED: no independent held-out 0–5 cm pH-in-water samples with sampling dates/method/license were obtained; WoSIS training overlap cannot be assumed absent"
    )
    report["forecast_validation"] = (
        "NOT MEASURED: current forward forecasts are not later observations; no QA-matched archived forecast/station pairs were obtained in this bounded run"
    )
    (ROOT / "docs/validation/evidence/reference-availability.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(
        json.dumps(
            {
                "reference_attempts": len(report["attempts"]),
                "station_candidates": len(report["stations"]),
                "statuses": [a["status"] for a in report["attempts"]],
            }
        )
    )


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--private", type=Path, required=True)
    asyncio.run(main(parser.parse_args().private))
