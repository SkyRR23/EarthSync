# EarthSync and the supplied OpenFarm checkout

Reviewed 14 November 2026. OpenFarm path: `D:/Nasa_spaceApp/openfarm/OpenFarm`,
commit `884a615`. This is a source inspection and an isolated calculation check,
not a deployed OpenFarm integration test. No OpenFarm code or crop thresholds
were copied into EarthSync.

| Area | OpenFarm checkout | EarthSync web feature |
|---|---|---|
| Purpose | Field monitoring, soil/weather intelligence and crop scores | Historical climate exploration and crop-sequence evidence checks |
| Application | Next.js, FastAPI, Celery, PostGIS, Redis, MinIO, TiTiler | Flutter web, Python service, actual shared Rust executable; separate Android FRB path |
| Climate/weather | Open-Meteo daily weather and forecast pipeline; temperature, rain, ET0, radiation, wind, soil moisture and VPD | NASA POWER historical temperature and rain, month coverage and Rust seasonal statistics |
| Satellite analysis | Sentinel-2 vegetation indices, field polygons and imagery processing | Map/imagery context; no computed vegetation or field-stress claim |
| Soil | SoilGrids globally; POLARIS for continental US; depth profiles, texture, pH, carbon, CEC and hydraulic estimates | Reported drainage; soil measurements remain unavailable |
| Crops | 68 hardcoded profiles; weighted soil/water/climate/stress scores | Explicit supplied-evidence checks; reference-only rice–pulse examples remain unknown |
| Rotation | Reviewed code scores individual crops, not a verified rotation calendar | Baseline and sequence candidates; transition/calendar feasibility remains unevaluated |
| Validation | CI has lint/type checks; API test step says `No tests yet` | Rust, Python boundary and Flutter tests, including actual-engine execution |

## What to adopt as product requirements

1. Visible readings, time ranges, units, source dates, missing-data states and
   charts alongside readable monthly values. These are added in this feature.
2. A soil panel: texture, pH, salinity, organic carbon and available-water
   estimates, each with depth, resolution, source, timestamp and uncertainty.
   These data are **not integrated yet**; never present regional model values as
   measured field samples.
3. Rainfall and temperature over a complete historical year before attempting
   seasonal comparisons. Web live mode now defaults to the previous completed
   calendar year; the captured mode retains its exact February 2024 window.
4. Field boundaries and vegetation history as a later, separate ingestion and
   validation project. OpenFarm's infrastructure is substantially broader than
   this local demo needs.
5. Crop profiles with per-fact citations, variety, production system, geographic
   applicability and review status before introducing suitability scores.

## Why not import the scoring rules directly

`services/api/app/core/soil_intelligence.py` defines `CropRequirements` and
`CROP_PROFILES` without per-fact citations or local evidence-review fields.
Its `assess_crop_suitability` combines soil 40%, water 25%, climate 20% and
stress 15%. Subscores begin at 1.0; absent values skip several penalties.

An isolated call against that exact local module confirmed:

```text
assess_crop_suitability({}, [], None) -> []
assess_crop_suitability({}, [], {}) -> 68 crops, all 100.0 / excellent
```

This demonstrates missing-data behavior in the calculation function, not proof
that a deployed API accepts empty dictionaries. The route in
`services/api/app/routers/soil.py` requires a soil profile and at least 90 weather
rows. However, it counts rows rather than valid observations for each metric,
and annualizes precipitation by `365 / day_count`. This needs separate coverage
and seasonal-representativeness validation. Its truthiness checks also turn a
zero precipitation sum or zero temperature statistic into `None`.

The local catalogue includes rice, groundnut and chickpea but no mung bean or
black gram keys. Its breadth does not directly fill EarthSync's Myanmar
rice–pulse evidence gap. Keep unknown conditions unknown and retain the actual
Rust engine; do not transplant these scores as verified agronomy.

## Source pointers

- `README.md`, `LICENSE` (BSD-3-Clause).
- `services/api/app/core/soil_intelligence.py`: catalogue and scoring.
- `services/api/app/routers/soil.py`: crop-suitability route and weather gate.
- `services/api/app/tasks/weather.py`: weather variables and derivations.
- `services/api/app/tasks/soil.py`: soil providers and source selection.
- `apps/web/src/components/field/soil-tab.tsx`: data, job and error presentation.
- `.github/workflows/ci.yml`: actual validation commands.

OpenFarm's broader data presentation is a useful reference. Its scoring logic
needs evidence review and missing-data safeguards before any reuse.
