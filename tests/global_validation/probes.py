"""Bounded supplemental source checks, never field-accuracy inference."""

import asyncio
import hashlib
import json
import math
from pathlib import Path
import httpx
from rasterio.io import MemoryFile
from rasterio.warp import transform
from shapely.geometry import Point, shape
from run import ROOT, RecordedTransport
from earthsync.platform_v1.providers.discovery import HlsDiscovery, DiscoveryQuery
from earthsync.platform_v1.models import FarmInput


async def main(private):
    sites = json.loads((ROOT / "tests/global_validation/sites.json").read_text())[
        "sites"
    ]
    rows = []
    soil = []
    cache = private / "runtime/captures"
    metas = [json.loads(p.read_text()) | {"key": p.stem} for p in cache.glob("*.json")]
    for s in sites:
        d = json.loads((private / "runtime" / s["id"] / "soil.json").read_text())
        match = next(m for m in metas if m["sha256"] == d["source_sha256"])
        raw = (cache / (match["key"] + ".body")).read_bytes()
        with MemoryFile(raw) as memory, memory.open() as ds:
            x, y = transform("EPSG:4326", ds.crs, [s["longitude"]], [s["latitude"]])
            expected = int(next(ds.sample([(x[0], y[0])]))[0])
            cell = next(c for c in d["cells"] if c["at_query_point"])
            assert (None if expected == -32768 else expected) == cell["raw"]
            assert shape(cell["geometry"]).covers(Point(s["longitude"], s["latitude"]))
            soil.append(
                {
                    "site_id": s["id"],
                    "status": "PASS",
                    "raw_cell": expected,
                    "ph": None if expected == -32768 else expected / 10,
                    "point_in_display_cell": True,
                    "classification": "SOFTWARE/SOURCE consistency; not independent soil accuracy",
                }
            )
    async with httpx.AsyncClient(
        timeout=25,
        headers={"User-Agent": "EarthSync-bounded-scientific-validation/1.0"},
    ) as client:
        for s in sites:
            zoom = 6
            n = 2**zoom
            x = int((s["longitude"] + 180) / 360 * n)
            y = int(
                (1 - math.asinh(math.tan(math.radians(s["latitude"]))) / math.pi)
                / 2
                * n
            )
            urls = {
                "osm": f"https://tile.openstreetmap.org/{zoom}/{x}/{y}.png",
                "gibs": f"https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/MODIS_Terra_CorrectedReflectance_TrueColor/default/2024-07-01/GoogleMapsCompatible_Level9/{zoom}/{y}/{x}.jpg",
            }
            for provider, url in urls.items():
                try:
                    r = await client.get(url)
                    r.raise_for_status()
                    assert r.content.startswith(
                        b"\x89PNG" if provider == "osm" else b"\xff\xd8"
                    )
                    rows.append(
                        {
                            "site_id": s["id"],
                            "provider": provider,
                            "status": "PASS",
                            "url": url,
                            "bytes": len(r.content),
                            "sha256": hashlib.sha256(r.content).hexdigest(),
                            "classification": "REAL display tile; not NDVI or crop-health observation",
                        }
                    )
                except Exception as exc:
                    rows.append(
                        {
                            "site_id": s["id"],
                            "provider": provider,
                            "status": "UNAVAILABLE",
                            "url": url,
                            "error": type(exc).__name__,
                        }
                    )
        transport = RecordedTransport(client, cache, 20)
        s = sites[0]
        try:
            discovery = await HlsDiscovery(transport).retrieve(
                DiscoveryQuery(
                    farm=FarmInput(
                        name="SYNTHETIC metadata query",
                        confirmed_point={
                            "latitude": s["latitude"],
                            "longitude": s["longitude"],
                        },
                        confirmed_on="2026-11-14",
                        production_system="rainfed",
                    ),
                    start="2024-07-01T00:00:00Z",
                    end="2024-07-31T00:00:00Z",
                )
            )
            (private / "hls-discovery.json").write_text(
                json.dumps(discovery, indent=2, default=str)
            )
            hls = {
                "status": "metadata_available",
                "records": len(discovery["records"]),
                "numeric_ndvi": "UNAVAILABLE: no authorized accepted raster/QA ingestion; no true-color substitution",
            }
        except Exception as exc:
            hls = {
                "status": "UNAVAILABLE",
                "error": getattr(exc, "code", type(exc).__name__),
                "numeric_ndvi": "UNAVAILABLE",
            }
    out = {
        "release_sha": "660b479c3ffb714cd1d489e1241c026ceae6ed67",
        "tiles": rows,
        "soil_raster_checks": soil,
        "hls": hls,
        "tls_verification_disabled": False,
    }
    (ROOT / "docs/validation/evidence/source-probes.json").write_text(
        json.dumps(out, indent=2) + "\n"
    )
    print(
        json.dumps(
            {
                "tile_checks": len(rows),
                "tiles_passed": sum(r["status"] == "PASS" for r in rows),
                "soil_checks": len(soil),
                "hls": hls,
            }
        )
    )


if __name__ == "__main__":
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("--private", type=Path, required=True)
    a = p.parse_args()
    asyncio.run(main(a.private))
