# 7G → 7X integration handoff

Branch: `feat/earthsync-geospatial-intelligence-v1`.
Exact parent/base: `edefc0c4dedf232e7ddb9704f6f2180a4936fcc3` (7W #27).
Isolated worktree: `/workspace/EarthSync-7G`. The draft targets the unchanged 7W
branch `feat/earthsync-crop-water-advisor-v1`. The exact delivery SHA is in the PR
body and can be checked with `git rev-parse HEAD`. No main/7X/#24–#27 changes,
automatic merge, public deployment or source-rule promotion were performed.

Read [capabilities](CAPABILITIES.md), [science/rights](SCIENCE.md),
[verification](VERIFICATION.md), [startup](LOCAL_WEB.md),
[OpenFarm/initial audit](AUDIT.md) and [localization/offline limits](LOCALIZATION.md).

## Delivered slices

- Slice 1 operational within its explicit geometry scope: actual Web map,
  confirmed point/boundary drawing/editing/undo/cancel, approximate area,
  device save/reopen and private immutable farm-revision persistence.
- Slice 2 unavailable: real NASA discovery accepted, no authorized/QA-accepted
  raster observation. No NDVI overlay/history is claimed. Earthdata 401 and
  ORNL MODIS 503 are documented; existing HLS numerical QA remains intact.
- Slice 3 operational for reference-only 0–5 cm modeled mean pH: exact accepted
  SoilGrids WebDAV manifest, native TIFF QA, real bounded cells, legend/opacity,
  raw units, provenance, missingness and saved source history. WCS is unchanged.
- Slice 4 partial: real official GFS temperature forecasts, verified model/valid
  times, native Kelvin conversion, regional support and limited sampled-freezing
  condition. Publication time, current station observations, precipitation and
  official warnings are unavailable. No unsupported threshold/alert is supplied.
- Slice 5 partial: dated farmer reports, crop identity search, calendar/date/stage,
  irrigation/drainage unknowns and a report/source-request timeline. Existing
  photos/crop history stay available separately. Translation/offline foundations
  are bounded and explicitly incomplete.

## Additive integration contracts

1. Device farm records retain profile version 1 with an optional GeoJSON
   `confirmed_polygon`. Existing point-only records remain valid. Explicit farm
   edits create a new confirmation revision, as in 7W. Do not attach old evidence
   to that revision automatically. Reuse the existing farm-link API and include
   the optional polygon; local/remote point and boundary equality are checked.
2. Keep the existing loopback/origin/ownership boundary, single-user principal,
   worker/deadline/request caps and Rust executable hash checks. New owned endpoints:
   `POST /soil-map/jobs`, `POST /forecast/jobs`,
   `GET /farms/{id}/intelligence`, `GET/POST /farms/{id}/observations`,
   and `GET /crop-identities?q=…`, all below `/api/platform/v1`.
3. Install new migration **003_observations.sql** after existing 001/002 without
   editing their checksums. It adds one farm/owner-bound reports table/index;
   there is no destructive migration/backfill. The migration-count test now
   expects three applied migrations. SQLite backup/restore includes the table.
4. Preserve new provider modules and the strict fixed-source transport additions.
   Never make the API accept arbitrary raster paths, URLs or credentials. The
   SoilGrids manifest hash is an accepted contract; a changed alias must fail
   closed for review. It does not authorize a WCS sentinel override.
5. `intelligence` lists up to 30 owned saved source jobs. They are reference
   snapshots, outside the Rust assessment Evidence pathway. Do not automatically
   promote forecast/soil/report outputs into accepted agricultural requirements.
6. Keep corrected CMR concept/title pairing; current UMM metadata omit the older
   ShortName/Version fields. Retain original granule metadata and nonnumeric flag.
7. Retain English labels/resources and the source-panel explicit semantics nodes.
   The accessibility test covers publication/warning limitations using cached real
   NOAA data and a mocked local transport. It must not become a fake live fallback.

## Safe 7X procedure

Review this draft above the exact accepted 7W head. Do not merge or cherry-pick
into a release worktree automatically. On a separately authorized integration
branch, reconcile accepted 7N/7P/7W/7V dependencies first, then review 7G's additive
schema/UI/provider changes. If the integration base moved, resolve the source
contracts and migration sequence explicitly; do not rewrite previous PRs, replace
catalogs, loosen a scientific gate or duplicate a migration to hide conflicts.

Build/pin the real Rust binary, validate all source restrictions and run the
commands in VERIFICATION.md with disposable private stores. Confirm current
SoilGrids manifest identity and actual NOAA GRIB times. Repeat real browser
acceptance under the integration origin and verify a stopped-service backup,
process restart and restore into a new directory. Missing providers must remain
missing. Review regional modeled support/unknown uncertainty with scientific
owners before any broader agricultural use. Global weather warnings, numeric
NDVI, field soil labs and complete offline/localized operation remain follow-ups.

## Resources and operating limits

- Soil operation: one ~3.52 MB VRT **metadata** response plus one ~722 KB test TIFF;
  no global raster is opened/downloaded. Transport cap is 4 MB per response.
  Source TIFF is 600×600 Int16; only ≤25 cells are visualized, without field mean.
- GFS operation: four tiny ≤16-cell temperature GRIB subsets. The parser caps each
  GRIB at 100 KB; actual test files are a few hundred bytes. No global forecast
  archive is downloaded. Longitude seams/poles or unexpected grids fail closed.
- One operation per provider at a time; uncached operations are limited to one
  per 30 seconds. Soil cache TTL 24 h; forecast cache TTL 30 minutes and run identity
  is in its key. Cache hits retain original source retrieval times/hashes.
- Existing 120-second job deadline, bounded queue/admission, store quotas and
  ≤30-snapshot history remain in force. No scheduler or polling after view disposal.
- Built Web assets are about 44 MB in this toolchain. The Flutter/Rust SDK/build
  caches are development tooling, not raster data or deployed private storage.
- Public basemap requests are on demand. No prefetch/offline tile pack, terrain
  provider or unreliable hybrid labels are enabled. Opening a map reveals its
  geographic tile area to that provider, not the private polygon/report.
