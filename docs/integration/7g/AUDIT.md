# 7G initial audit

Base: `edefc0c4dedf232e7ddb9704f6f2180a4936fcc3` (7W #27), branch
`feat/earthsync-geospatial-intelligence-v1`, isolated `/workspace/EarthSync-7G`.
No AGENTS.md exists in this checkout. Read before implementation: 7W
HANDOFF_7X, VERIFICATION, COVERAGE, SCIENCE, LOCAL_WEB and 7P HANDOFF_7N.

## Existing paths and decisions

- Flutter `location_screen.dart` already uses flutter_map 8.3.2 (BSD-3-Clause),
  latlong2 0.10.1 (Apache-2.0), Web canvas, OSM and NASA GIBS. Retain this native
  Flutter map rather than add a JS MapLibre bridge and another dependency graph.
  OSM data: ODbL; public tile service policy prohibits bulk/offline prefetch.
  NASA GIBS MODIS true color: dated regional imagery, maximum native zoom 9,
  no numeric NDVI. Satellite and hybrid modes will clearly retain these limits.
  No accepted terrain source; no terrain mode advertised.
- Device `HomeProfile` stores confirmed points in SharedPreferences. Backend
  FarmInput already accepts an optional EPSG:4326 exterior polygon with Shapely
  topology/point association checks and antimeridian rejection. Farm links use
  immutable confirmation revisions; preserve that behavior and point-only farms.
- Platform private SQLite already owns farms/evidence/jobs/history/photos and
  pins Rust v0.3. Reuse its loopback/origin/ownership controls and bounded jobs.
- `platform_v1/satellite.py` already validates local HLS L30/S30 v2 30 m aligned
  red/NIR/Fmask, scaling, nodata, conservative cloud QA and interior pixels.
  `providers/discovery.py` provides bounded NASA CMR discovery, not raster access.
- SoilGrids REST is paused. Existing strict WCS pH gate rejects absent nodata.
  Previous real WCS captures failed that gate; never assign a guessed sentinel.
  WebDAV VRT metadata alone does not establish numerical integration.
- Environmental Open-Meteo probe distinguishes modeled current conditions and
  forecasts but withholds use because the generic API lacks an issuance time.
  Preserve that gate unless a verified issued product can be retrieved.
- POWER history, native ET0, 7P catalog and all 60 blocked 7V candidates remain
  unchanged. Existing crop history/photos are reusable farmer reports.

## OpenFarm reference audit

Audited https://github.com/superzero11/OpenFarm at
`884a61567dd0d149214090baf9edebc533a2a0df` (shallow read-only reference clone).
Root LICENSE is BSD-3-Clause, copyright 2026 OpenFarm Contributors: source
redistributions must retain copyright/conditions/disclaimer; binary distributions
must reproduce them in accompanying materials; no endorsement by contributors.
No OpenFarm code is copied into this implementation.

Inspected draw-map.tsx, map-style-switcher.tsx, tasks/pipeline.py (STAC, bounded
COG windows), tasks/indices.py, tasks/ndvi.py, tasks/soil.py and web package.json.
Patterns: explicit draw/edit/save state, initial boundary restore, preserving
geometry across base layers, aligned native band windows and separate QA.
OpenFarm uses React/MapLibre/MapboxDraw, STAC Element84 Sentinel-2, rasterio,
Celery/Postgres/PostGIS and a tiler. These are not substitutes for EarthSync's
Flutter/FastAPI/Rust/SQLite architecture or NASA-centered evidence contracts.
Transitive dependencies and data/tile service terms have independent obligations;
a BSD root license does not license arbitrary imagery or dependency code.

Do not reuse OpenFarm's `< -9990` heuristic where TIFF nodata is absent, zero
fill for missing remote raster support, soil heuristics or crop alert thresholds.
Those patterns do not meet EarthSync's required scientific integrity gates.
