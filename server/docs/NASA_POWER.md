# NASA POWER source, normalization and verification status

Configured official endpoint:
`https://power.larc.nasa.gov/api/temporal/daily/point`

Query: `parameters=T2M,PRECTOTCORR`, `community=AG`, requested latitude/longitude,
`start=YYYYMMDD`, `end=YYYYMMDD`, `format=JSON`, `time-standard=LST`.
Split at calendar-year boundaries for bounded daily responses; do not use the
monthly API's daily-average precipitation rate as a monthly accumulation.

Official documentation targets (must be rechecked when network access is enabled):

- https://power.larc.nasa.gov/docs/services/api/temporal/daily/
- https://power.larc.nasa.gov/docs/methodology/meteorology/
- https://power.larc.nasa.gov/#resources (parameter/data access documentation)

Implementation expectations: T2M is the daily mean temperature at 2 m, returned
in `C`; PRECTOTCORR is bias-corrected precipitation, daily rate in `mm/day`.
These are gridded meteorological model/reanalysis products (MERRA-2 lineage),
not direct observations at the requested farm. Nominal meteorological spatial
support is 0.5° latitude × 0.625° longitude; source geometry/header are retained
so this nominal statement is not a claim of field-scale accuracy. Rainfall variable
naming follows Rust, but NASA total precipitation can include non-rain precipitation;
it is not an estimate of irrigation or plant-available water.

The adapter rejects a response with different/missing units, fill value or LST
marker rather than guessing. Each daily precipitation rate × one day contributes
mm to the monthly sum. Monthly T2M is the equally weighted arithmetic mean of
all daily means in the source's LST calendar. Every date must have a finite numeric
value unequal to the declared fill value. Negative precipitation is invalid;
zero precipitation and negative Celsius are valid. Null, absent, fill, boolean,
string or nonfinite values remain missing, independently by variable. A missing
day nulls the entire month's aggregate. No interpolation, scaling partial samples,
forecast substitution, or invented quality thresholds. Coverage is not scientific
validation; POWER values and methodology can be revised upstream.

## Live verification blocker — 14 November 2026

Both the official daily API (16.85 N, 96.15 E, February 2024) and official
methodology/API documentation requests failed at the environment egress proxy
with HTTP 403 / CONNECT tunnel denied. The implementation's source semantics
above are explicit expectations, not a claim that the current live parameter
catalog, documentation, spatial support or response were verified in this run.
Mock fixtures validate normalization against those expectations only.

`power.larc.nasa.gov` was added to the environment configuration draft; applying
network changes in environment settings is still required. No normalized real
example is committed because no real response was obtained. Do not relabel the
mock fixture as real data. Retry after network access is applied:

```sh
cd server
.venv/bin/python -m earthsync.smoke --output examples/nasa_power_real.json
```

The command makes a real request for leap-year February 2024 at 16.85/96.15,
checks units/time standard and full coverage, and only then writes the normalized
response with exact request, original metadata and UTC retrieval timestamp.
Review the official documentation and header source lineage before accepting
that file. Failure exits nonzero and writes no new example. A pre-existing output
is not evidence of a new successful run; check timestamp/exit status. This test is
explicit and separate from network-independent pytest.
