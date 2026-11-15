# NASA POWER live verification — 14 November 2026

The previously blocked daily API and official documentation now return HTTP 200.
No environment configuration was recreated, updated or published in this task.
The attached-name reference `EarthSync_Data_API_Inventory_2026.md` was not available
in the chat filesystem; the findings below rely on the official sources directly.

## Official source review

Read on 14 November 2026:

- [Daily API](https://power.larc.nasa.gov/docs/services/api/temporal/daily/): daily
  averages/minima/maxima, native source resolution, default LST, explicit
  `time-standard=LST|UTC`, coverage starting 1 January 1981. LST is a 15-degree
  swath representing solar noon at its middle longitude; it is **not** Myanmar
  civil time (UTC+06:30) or a point-specific longitude timestamp.
- [Meteorological sources](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/):
  MERRA-2 assimilation/reanalysis, native 0.5° latitude × 0.625° longitude,
  spatial grid averages; daily means derive from hourly values. POWER's recent
  continuation can use GEOS-IT, and records may be revised as MERRA-2 arrives.
  The older `/docs/methodology/meteorology/` URL returned 404 and is replaced here.
- [Official parameter catalog](https://power.larc.nasa.gov/api/system/manager/parameters?community=AG&temporal=daily):
  `T2M`: average air (dry bulb) temperature at 2 m, units `C`;
  `PRECTOTCORR`: average MERRA-2 bias-corrected total surface precipitation,
  units `mm/day`. The source field in this catalog is generic `SOURCE`; lineage
  is established from methodology plus the actual response, not that label alone.

`examples/nasa_power_source_review.json` stores the exact two catalog entries,
review timestamp, official URLs and hashes of the retrieved documentation HTML.
No claim of direct field measurement, farm-scale precision or agronomic validation
follows from provider documentation or coverage.

## Real Yangon February 2024 result

Request endpoint: `https://power.larc.nasa.gov/api/temporal/daily/point`

Parameters: `parameters=T2M,PRECTOTCORR`, `community=AG`, `latitude=16.85`,
`longitude=96.15`, `start=20240201`, `end=20240229`, `format=JSON`,
`time-standard=LST`.

The initial capture returned HTTP 200, POWER Daily API `v2.10.3`, header source
`["MERRA2"]` (also HTTP `x-data-sources: merra2`), fill `-999.0`, explicit LST
and matching start/end. There are exactly 29 valid daily values per variable,
no missing dates/fills, and no source warning messages. Source geometry retains
requested coordinates and elevation 10.91 m; it does not establish a cell centroid.

The existing smoke was run successfully, then repeated after adding lineage and
interval guards. `examples/nasa_power_real.json` records the successful retrieval's
UTC timestamp, query/header/units, spatial support and completeness reasoning.
`tests/fixtures/nasa_power_yangon_202402_live.json` retains the initial real raw
capture for offline replay; it is distinct from `nasa_daily_mock.json`.

- Full-month precipitation: **0.04 mm** (daily rate × 1 day, summed for 29 days).
- Mean T2M: **28.03655172413793 °C** (equal mean of all 29 daily means).
- `rainfall_complete` and `temperature_complete`: both true.
- Data kind: **modeled**; source is reanalysis/assimilation, never direct farm data.

Totals use the returned daily values at their published precision. No hourly raw
completeness or independent scientific quality check is implied. Total precipitation
may include non-rain precipitation; Rust's `rainfall_mm` name is a compatibility
mapping, not a hydrological partition. This dry-month sample does not establish
wet-season performance or crop water availability.

The normalized real example passed actual `analyze_season_json` in a compiled
external Rust consumer: 29 calendar days, 0.04 mm and the same temperature.
The v0.2 branch's `engine/src/seasonal.rs` is identical to this existing schema.
No engine/Flutter files were edited.

## Guardrails and limitations

Units must exactly match `C` and `mm/day`, time standard must be LST, source list
must be exactly `["MERRA2"]`, interval header must match the request, and a finite
numeric fill sentinel is required. Any drift yields a safe 502 (no guessed units
or mislabeled GEOS-IT). This deliberately limits P0 to homogeneous MERRA-2;
recent windows can fail with `UPSTREAM_SOURCE_CHANGED`. Supporting GEOS-IT/mixed
series requires an explicit later provenance contract and aggregation decision.

Each variable requires every calendar date with a finite numeric value unequal
to fill. Precipitation must be nonnegative. Null/absent/fill/string/boolean/nonfinite
values are missing; any gap nulls that variable's monthly aggregate. Zero rain and
negative Celsius remain valid. No gap filling, partial-sample scaling or forecasts.
Coverage flags attest daily record coverage only, not measurement accuracy.

## Reproduce the live smoke

Linux, from `server/` with dependencies installed:

```sh
.venv/bin/python -m earthsync.smoke --output examples/nasa_power_real.json
```

Windows PowerShell, from the repository root on the backend branch:

```powershell
cd server
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock
.\.venv\Scripts\python.exe -m pip install --no-deps -e .
.\.venv\Scripts\python.exe -m earthsync.smoke --output examples/nasa_power_real.local.json
if ($LASTEXITCODE -ne 0) { throw "NASA live smoke failed; do not use an older output as new evidence" }
```

The smoke writes only after successful metadata/unit/lineage checks and complete
coverage. Inspect the exit status and new retrieval timestamp. Values may change
with upstream revisions; a committed capture is historical evidence, not a promise
of permanent connectivity or identical future climate values. Live requests are
explicit and excluded from Python CI; offline replay is clearly labeled.


## API reliability follow-up

The integration task repeated real HTTP checks and captured an October 2026
GEOS-IT response separately from the existing MERRA-2 fixture. See
[verification evidence](RELIABILITY_VERIFICATION.md), the
[source-verified GEOS-IT contract proposal](GEOS_IT_CONTRACT_PROPOSAL.md), and
[Python 3.13 / Windows / Wi-Fi / USB commands](WINDOWS_RUNBOOK.md). The current
adapter still rejects unsupported lineage; no GEOS-IT values are relabeled.
