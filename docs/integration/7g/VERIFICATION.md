# 7G verification receipts

Verified in the isolated 7G Cloud worktree; source captures and tests use UTC
2026-11-14 (2026-11-15 in Asia/Rangoon). There was no public deployment/merge.

| Check | Final result | Evidence |
|---|---|---|
| Full Python backend + operations, compatibility snapshots and actual native consumers; NASA/HLS/SoilGrids WebDAV/GFS live opt-ins | **435 passed, 1 skipped** | `evidence/python-final-regression.log`. The one skip is the separate legacy WCS live numeric probe, not WebDAV. |
| Rust regressions | **123 passed**, zero failed/ignored | `evidence/rust-regression.log`; Rust source unchanged. |
| Full Flutter tests, actual native bridge loaded | **117 passed**, 3 opt-in live tests skipped | `evidence/flutter-final-regression.log`; new geometry and accessibility checks included. |
| Flutter analyzer / Web build | **No issues / successful build** | `evidence/flutter-analyze.log`, `flutter-web-build.log`. |
| New actual Chromium → Flutter → API → saved source views | **14 stages passed**, zero unhandled page errors | `evidence/browser/results.json`; source jobs, real map tiles and screenshots alongside it. |
| Final built-asset CLI reproduction | **14 stages passed**, zero unhandled page errors | `evidence/browser-final-build/results.json`, `browser-script-reproduction.log`; same real-data flow after the boundary comparison improvement. |
| Inherited actual 7W browser workflow | **8 stages passed**, zero unhandled page errors | `evidence/browser-7w/results.json`: live POWER → Rust ET0 → SQLite → v2 reference → saved assessment → assistant → refresh/phone/outage. |
| Separate fresh ISRIC/GFS smoke tests | **2 passed** | `evidence/live-7g-tests.log`, `soil-webdav-fresh-live.json`, `gfs-fresh-live.json`; both `cache_hit=false`. |
| Separate NASA POWER and HLS discovery smoke | **2 passed, 1 skipped** | `evidence/live-nasa-hls.log`; that skip is the unselected WCS probe. Discovery is not accepted NDVI. |
| Actual server process restart and independent backup/restore | **Passed**, exact rows retained | `evidence/restart-and-restore.json`: farm links/polygons, observations, jobs, evidence, decisions, history and migrations compared by content hashes; real Rust readiness passed after restart. |
| Scientific raster/geometry QA | Passed in the full suite | Cached real TIFF/GRIB and synthetic bad-grid/unit/time/nodata/topology inputs; original HLS/Fmask tests retained. |
| Formatting/lint/dependency integrity | Passed | `evidence/static-checks.log`; unchanged dependency locks. |

No Windows, Android/Gradle, Docker build, hosted identity, public hosting,
complete offline app, independent agronomic acceptance or NDVI numeric integration
is claimed. Provider availability/forecast skill are distinct from software tests.

## Evidence classifications

- **Fresh real provider data:** dedicated opt-in ISRIC WebDAV and NOAA GFS tests
  use new private stores and actual bounded source bytes. Their receipts preserve
  `cache_hit=false`, retrieval times, units, native support and response hashes.
  NASA POWER/HLS discovery live tests also contacted their actual providers.
- **Browser cached real source data:** the canonical 7G pH/forecast source jobs
  truthfully report `cache_hit=true` when reusing the private source cache from
  actual prior retrievals. The browser still creates real jobs and reads the
  actual private SQLite/API pipeline; no browser response is mocked or substituted.
  Retrieval timestamps are not refreshed just because the UI reopened a snapshot.
- **Cached real numerical regression:** the 722 KB ISRIC TIFF and 182-byte NOAA
  GRIB fixture, with source URL/hash/license receipts, test extraction, missingness,
  native units and registration. Cached CMR UMM metadata test collection identity.
  Test query/retrieval contexts are fixtures, not claims of live observations.
- **Synthetic numerical/fault fixtures:** geometry rings, crossing/degenerate
  cases, bad grids/nodata/units/dates, existing HLS pixel arrays, provider outages
  and ownership cases. These verify failure behavior, not field conditions.
- **UI mock transport:** the accessibility test uses a cached real NOAA result
  through a mocked local transport to verify that issuance/warning limitations
  remain in the semantics tree. This is not a fake live provider or UI fallback.
- **Farmer reports/photos/farms used in acceptance:** explicitly labeled software
  test inputs, no agricultural ground truth. Existing photo workflows were retained;
  no fabricated image was used as environmental evidence in 7G.
- **7W browser outage:** its existing explicitly injected transport abort remains
  a simulated network fault; no real NASA outage is claimed.

## Actual browser conditions and screenshots

The 7G runner uses installed Chromium and actual compiled Flutter Web assets,
loopback services, SQLite and the compiled Rust executable. OSM and NASA GIBS
requests return real tiles. Flutter Web semantics are enabled for control lookup;
raw canvas gestures temporarily pass through that test semantics overlay. No
source data, geolocation or provider API response is injected.

This managed computer's Chromium rejected the environment HTTPS proxy certificate,
while normal server/Python TLS validation succeeded. Automatic approval review
rejected a persistent proxy-CA trust-store change because it would broaden browser
trust. The safer permitted alternative was an **ephemeral test-context-only**
`ignore_https_errors` setting, recorded in the 7G receipt. No persistent trust-store
change, application TLS exception or weakened provider transport was made.

Final reviewed screenshots:

- [Polygon confirmation, desktop](evidence/browser/polygon-confirmed-desktop.png)
- [Dated true-color satellite mode](evidence/browser/satellite-mode.png)
- [Actual ISRIC pH cells, legend and boundary](evidence/browser/soil-map-desktop.png)
- [Actual NOAA valid times and explicit limitations](evidence/browser/forecast-desktop.png)
- [Forecast at phone width](evidence/browser/mobile-source-snapshots.png)
- [Farmer report timeline](evidence/browser/field-timeline.png)
- [Inherited NASA/Rust ET0](evidence/browser-7w/real-water-calculation-desktop.png)

## Reproduce

Follow LOCAL_WEB.md and use **disposable private stores**: browser tests create
labeled farms/reports/assessments. Keep compatibility exports outside checkouts.

```sh
cd "$EARTHSYNC_REPO"
export PYTHONPATH="$EARTHSYNC_REPO/server"
export EARTHSYNC_TEST_V03="$EARTHSYNC_REPO/engine/target/debug/examples/v03_demo"
python server/platform-v1/tools/prepare_compat.py /absolute/new/7g-compat \
  --revision edefc0c4dedf232e7ddb9704f6f2180a4936fcc3
export EARTHSYNC_COMPAT_ROOT=/absolute/new/7g-compat
EARTHSYNC_LIVE_PROVIDERS=nasa,hls,soil_webdav,gfs python -m pytest -q -rs server/tests ops/staging/tests
cargo test --locked --manifest-path engine/Cargo.toml
cd app
LD_LIBRARY_PATH="$EARTHSYNC_REPO/app/rust/target/release" flutter --suppress-analytics test --reporter expanded
flutter --suppress-analytics analyze
cd ..
python scripts/browser_7g.py --base-url http://127.0.0.1:8093 \
  --platform-url http://127.0.0.1:8031 --output /absolute/new/7g-browser
python scripts/browser_7w.py --base-url http://127.0.0.1:8093 \
  --platform-url http://127.0.0.1:8031 --output /absolute/new/7w-regression
```

Only on this managed proxy, add the 7G runner's explicit
`--cloud-proxy-certificate-exception` flag. Normal browser runs retain certificate
verification. Do not run several acceptance contexts against the same private
single-user API simultaneously: its existing global request-rate limit remains
active. Do not weaken that limit or source gates to pass tests.
