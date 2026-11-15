# EarthSync global validation — immutable release candidate

Subject: `660b479c3ffb714cd1d489e1241c026ceae6ed67`. Validation date: 2026-11-15 UTC. This is the integrated **candidate**, not a released main build. Main remains `1ea3df7b09637cf8162f834411d830aa8621590c`.

EarthSync's reference ET0 arithmetic is numerically verified on the accepted inputs tested. Its environmental source handling works at the sampled public locations. Global field accuracy, crop suitability, soil-field accuracy and forecast skill are **not established**. There is no defensible overall accuracy percentage.

## Measured results

| Measurement | Result | Interpretation |
|---|---|---|
| Public research sites | 12; 6 Myanmar; 6 countries; 6 continents | P0 count/geographic diversity met; Sagaing unavailable and explicitly excluded |
| Historical retrieval | 24/24 seven-day windows; 168 site-days | REAL NASA POWER production pathway, January/July 2024 only |
| Rust FAO-56 vs independent equations | 149/149 accepted days pass; max absolute difference 1.332e-15 mm/day | Numerical implementation agreement, not field ET/irrigation accuracy |
| Withheld ET0 | 19 days | {'FROST_POINT_CONVERSION_UNVALIDATED': 15, 'RADIATION_METHOD_OUTSIDE_SUPPORTED_DOMAIN': 3, 'NEGATIVE_VAPOUR_PRESSURE_DEFICIT': 1}; never replaced with zero |
| Weather vs station reports | 8 site/season/variable groups × 7 days; MAE 1.06–2.46 °C | Descriptive only: below predeclared 10-day per-group minimum and independence unknown |
| Soil extraction | 12/12 original raster query-cell and scaling checks pass | 250 m modeled 0–5 cm pH; no independent field-error metric |
| GFS | 2 sites × 4 temperature records; conversion/time checks pass | No later matching observations; no forecast-skill score |
| Map sources | 24/24 HTTPS OSM/NASA GIBS tile requests pass | Real display tiles; true color is not NDVI; TLS verification enabled |
| Three-strategy workflow | 12/12 native Rust/SQLite cases; 36 decisions | SYNTHETIC reported plans/history, real/cached-real environmental inputs; explicit scope |
| Browser reopening | 12/12 sites passed | Actual compiled Flutter, saved-farm selection and saved-comparison reopening; see browser scope/failures |
| Executable crop rules | 0 approved; all 60 blocked | Suitability accuracy is not measurable |

[Site matrix](LOCATION_TEST_MATRIX.csv), [weather](WEATHER_VALIDATION.csv), [soil](SOIL_PH_VALIDATION.csv), [ET0](ET0_NUMERICAL_VALIDATION.csv), [forecast](FORECAST_VALIDATION.csv), [workflow](ROTATION_WORKFLOW_RESULTS.md), [scientific gates](SCIENTIFIC_ELIGIBILITY_REPORT.md), [provider evidence](PROVIDER_AVAILABILITY.md), [limits](BUGS_AND_LIMITATIONS.md), [reproduction](REPRODUCTION_GUIDE.md).

## Study design and exclusions

The public site manifest and protocol were frozen and SHA-256 pinned before model retrieval; no site was replaced based on model results. Published agricultural-research coordinates are not private farmer records or proof of present land use. Geographic conditions span delta, dry zone, highland, coastal/lowland, continental and Southern Hemisphere agriculture. Only source-supported climate classes are recorded; unknown classes remain unknown.

The six Myanmar tested areas are Ayeyarwady, Bago, Mandalay, Magway, Shan and Yangon. Sagaing remains unavailable because candidate Zaloke coordinates could not be reconciled. Expansion to 20 sites, other suggested countries, 2025, transitions and documented extremes was not completed. Two fixed weeks are not annual or multi-year accuracy coverage.

NOAA Global Hourly station data were obtained for two US sites after HTTP-200 HTML responses from old annual URLs were rejected. Only accepted temperature QC flags and days with ≥18 distinct hourly bins were used. NASA hourly UTC/LST responses independently checked the −6-hour day offset (66 matching timestamps per US site); these audit responses never replace production daily values. Grid-to-point, elevation, reporting-frequency and assimilation overlap limitations remain. Rainfall accumulation windows were not reconciled, so precipitation-error metrics are not calculated. Daily mean temperature is not a supported output in the tested water-input contract.

Original raw values and captures stay in a private local evidence directory; public receipts contain public research query coordinates, source URLs, units, dates and content hashes. A new run must retain its own capture timestamps and must not overwrite this baseline evidence.

## Release decision

**Do not merge main.** The integrated release has [11 green exact-candidate CI workflows](evidence/release-ci.json); the [three source PR heads](evidence/release-heads.json) are unchanged. The additional local harness has five passing tests and the selected regression suite has 81 passing tests (including those five), with SYNTHETIC/MOCKED software fixtures labeled separately. However, mandatory accepted quantitative NDVI, local Windows interactive acceptance, independent agricultural review and other stated release limitations remain. This validation branch changes only tests/reports; it does not repair production science, alter eligibility or manufacture a released build. See the existing [final release verification](../release/VERIFICATION.md) and the candidate's release documents under `docs/`.
