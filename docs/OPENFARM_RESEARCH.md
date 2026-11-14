# OpenFarm source inspection

Reference: https://github.com/superzero11/OpenFarm at commit
`884a61567dd0d149214090baf9edebc533a2a0df` (inspected 14 November 2026).
Read source directly; no backend installed or code copied/adapted into the engine.

## Algorithms actually present

- `services/api/app/core/soil_intelligence.py`: crop profiles, sampling-zone
  construction, crop suitability, nutrient-risk classification, carbon estimates,
  soil/weather stress and alert evaluation. Crop requirement dataclasses include
  pH, available water capacity (AWC), texture, drainage, SOC, CEC, rainfall,
  temperature and drought/flood tolerance. These are not local evidence records.
- `assess_crop_suitability`: soil/water/climate/stress pillar weights of
  40/25/20/15 percent, multiplicative penalties, numeric scores and rating cutoffs.
  Missing weather dictionary returns no results; an existing dictionary with
  absent metrics skips penalties while pillar scores start at 1.0. This can make
  absent evidence look favorable. Do not adopt this behavior or its weights.
- `compute_soil_weather_stress`: compares a 30-day balance with root-zone AWC;
  uses drainage, drought index and surface-moisture thresholds. A balance relative
  to capacity is not a measured root-zone storage trajectory or paddy water budget.
- `services/api/app/tasks/weather.py`: `_calculate_gdd` computes
  max(0, (Tmax + Tmin)/2 - base), default base 10 °C. Pure arithmetic can be ported
  with boundary tests, but crop/stage base and any upper cap need cited profiles.
- `_update_water_balance`: SQL rolling precipitation minus reference ET0 over
  30 rows; coalesces missing values to zero. Its index divides rolling balance by
  daily-balance standard deviation, without subtracting a historical mean. It is
  not established here as SPI/SPEI. Thirty rows need not be 30 consecutive days;
  completeness and comparable baseline validation would be needed in Rust.
- `services/api/app/tasks/soil.py`: SoilGrids WCS/POLARIS acquisition, property
  unit conversions, texture/drainage classification, optional Rosetta hydraulic
  estimates, layer AWC, root-zone summaries and heuristic soil risks. POLARIS is
  US-focused, not a Myanmar input. `_compute_layer_awc_mm` uses
  max(0, FC_vol_percent - WP_vol_percent) × thickness_cm × 0.1, requiring
  correctly converted percentages and valid layer depths.

## Reuse decision

Pure GDD, explicit unit conversions and layer water-capacity arithmetic can be
implemented independently of Celery, database sessions, rasters or the web stack.
They are candidates, not implemented features. SQL/weather acquisition and WCS
pipelines belong with P2's backend, not the phone's pure library.

Our current monthly fixture lacks daily Tmax/Tmin, ET0, hydraulic layer profiles,
FC/WP, crop-stage coefficients, validated local calendars and crop production
systems. Annual rainfall alone cannot support these stress calculations. Paddy,
rainfed lowland and upland rice need distinct profiles and management context.
Do not label mung bean/black gram suitable until P2 supplies local evidence.
No numerical crop-score calibration or Myanmar validation was established by
this source inspection. Thresholds/defaults require source-by-source review.

## Licensing boundaries

Root LICENSE is BSD-3-Clause, copyright (c) 2026 OpenFarm Contributors.
Any future copied/adapted code must retain copyright, license conditions and
full disclaimer; binary redistribution must reproduce them in accompanying
materials, and contributor names cannot imply endorsement. This inspection found
one LICENSE path in the checkout; that does not clear every dependency or dataset.
SoilGrids, POLARIS, Open-Meteo, Rosetta and crop facts each require their own
version, terms, attribution and regional-validity checks before reuse. No data
assets or algorithm code are redistributed by this increment.
