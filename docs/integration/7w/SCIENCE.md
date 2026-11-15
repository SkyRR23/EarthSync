# 7W scientific contract and limits

This is a historical environmental computation and reference-inspection workflow.
It is not validated crop suitability, a yield/profit forecast, a forecast service,
or an irrigation prescription. All 7P files and agricultural gates are unchanged.

## Official NASA parameter acceptance

Policy `power-fao56-inputs.v1` uses the existing 7I transport and 7J daily parser
guards. Each parameter is fetched separately; an aggregate header cannot hide
its lineage. The existing `power-daily-merra2.v1` contract remains unchanged.

| Parameter | Meaning / original unit | Accepted header sources | Use |
|---|---|---|---|
| T2M_MIN | Minimum hourly 2 m air temperature during the day, C | MERRA2, POWER | Tmin, not instantaneous field minimum |
| T2M_MAX | Maximum hourly 2 m air temperature during the day, C | MERRA2, POWER | Tmax |
| PRECTOTCORR | Mean MERRA-2 bias-corrected precipitation rate, mm/day | MERRA2 | Complete daily rates integrated over one-day intervals in Rust |
| T2MDEW | 2 m dew/frost point, C | MERRA2 | FAO-56 Eq.14; negative values withheld pending frost-phase semantics |
| WS2M | Mean 2 m wind speed, m/s | MERRA2, POWER | Already at reference height; no 10 m conversion |
| PS | Surface atmospheric pressure, kPa | MERRA2 | Eq.8; no unnecessary elevation-derived replacement |
| ALLSKY_SFC_SW_DWN | Direct plus diffuse downward shortwave irradiance on a horizontal surface, MJ/m²/day | SYN1DEG | Solar energy Rs; not net radiation or crop ET |

The actual official manager catalog and selected exact definitions are retained in
`evidence/nasa-parameter-catalog.real.json` and `nasa-parameter-definitions.json`.
`documentation-receipts.json` records URLs, completion times, status, size and hashes.
Official references:

- [POWER daily API and time standards](https://power.larc.nasa.gov/docs/services/api/temporal/daily/)
- [POWER meteorological lineage](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/)
- [POWER energy-flux lineage](https://power.larc.nasa.gov/docs/methodology/data/sources_fluxes/)
- [POWER SYN1deg methodology](https://power.larc.nasa.gov/docs/methodology/data/derived/syn1deg/)

MERRA-2 meteorology and CERES SYN1deg radiation are **distinct products**, with
0.5° × 0.625° and 1° × 1° native support respectively. They supply different
meteorological variables over the same requested point and explicit NASA LST
24-hour date. They are not averaged, relabeled as a common grid or substituted
for one another. This is a regional reference estimate using the POWER products;
there is no independent field validation or quantified uncertainty interval.
The exact SYN1deg sub-edition is not asserted from its abbreviated API header;
the current methodology describes the edition family, while the response hash
pins the actual delivered values. The API version is not a science-data release.

API v2.10.3, exact parameter keys/units, dates, `LST`, fill value, source headers,
geometry and 7J's three-decimal geometry tolerance are required. Original geometry,
model elevation, requested high-precision point, headers, response hash, retrieval
time and every missing date/value survive. A returned query point does not locate
the exact native grid cell. LST is a solar-time swath, not a civil farm calendar.
No monthly-to-daily interpolation or provider substitution occurs.

The water input contract starts in 2001. Earlier SRB periods, FLASHFlux, GEOSIT,
mixed transition headers and changed API/unit contracts remain unavailable. A
new authoritative source is not necessary for the accepted warm-weather historical
subset; extending unsupported periods/phase semantics needs a separate review.

## FAO-56 computation and numerical verification

The only ET0 implementation is `engine/src/v03/water.rs`, invoked through the same
hash-pinned `v03_demo` executable with `--water-stdin`. The existing v0.3 crop
request wire shape and ETc implementation are unchanged. Python validates and
projects data; Flutter and the assistant do not calculate water quantities.

The versioned pure method is `fao56-daily-pm.v1`:

```
ET0 = [0.408 Δ (Rn − G) + γ 900/(Tmean + 273) u2 (es − ea)]
      / [Δ + γ (1 + 0.34 u2)]
```

FAO-56 equations 6, 8, 9, 11–14, 21, 23–25, 37–40 and 42 supply the method.
Mean temperature is (Tmin+Tmax)/2; saturation pressure uses both extrema; actual
vapour pressure uses daily dewpoint. Solar radiation is already MJ/m²/day for
community AG. Pressure is already kPa and wind is already m/s at 2 m. There is
no hidden kWh, hPa, 10 m wind or monthly conversion. Reference-grass albedo is
0.23, Stefan–Boltzmann constant is 4.903e−9 MJ K⁻⁴ m⁻² day⁻¹, and daily G=0 is
the FAO reference-surface assumption, not an observed field soil heat flux.
All inputs and intermediates, including both PM numerator terms, are persisted.

The clear-sky ratio is capped at 1 as specified by FAO-56 Eq.39. Polar night,
negative cloudiness/humidity factors, negative ET0, missing inputs, inconsistent
extrema, negative vapour-pressure deficit and below-freezing Dew/Frost Point
conversion are withheld. There is no lower-ratio clamp, preceding-day borrowing,
invented day, Hargreaves substitute or negative-to-zero replacement.

FAO Chapter 4 Example 18 (Uccle) is the numerical oracle: the published rounded
inputs/intermediates produce ET0 about 3.88 mm/day (tolerance 0.03 mm/day), with
separate assertions for extraterrestrial/net radiation, vapour pressure and slope.
An equivalent dewpoint represents the example's published actual vapour pressure;
this is labeled software input, not a new weather observation. FAO Chapter 3
Example 8 independently checks southern-hemisphere radiation (32.2 MJ/m²/day,
tolerance 0.05). Dates, frost, missingness and duplicate-day tests check rejection.
Sources: [FAO Chapter 3](https://www.fao.org/4/X0490E/x0490e07.htm),
[FAO Chapter 4](https://www.fao.org/4/X0490E/x0490e08.htm).

The original seven-day Iowa capture has complete rainfall (59.97 mm), six usable
ET0 days and a missing ET0 on July 2 because Eq.39's cloud factor is negative.
Its ET0 period total is null; the partial sum is explicitly labeled. A separate
live five-day browser request is checked independently; it is not reconstructed
by dropping the missing day from that seven-day response.

## Crop water, field balance and future rules

Rust v0.3 already computes ETc=Kc×ET0 when independently accepted, applicable
stage rules and complete aligned inputs are supplied. None of 7P's profiles has
such acceptance or complete stage offsets. No profile is promoted in 7W, so real
ETc remains unknown. The existing synthetic Rust tests exercise the arithmetic;
they do not demonstrate accepted farm ETc.

`water_dependencies()` persists separate null outputs and exact dependencies for
ETc, effective rain, soil storage, root-zone depletion, net irrigation, gross
irrigation, delivered availability and stress. There is **no executable field
water-balance model yet**. Rainfall is not subtracted from ET0 and called irrigation.
Rainfed observations do not establish adequate supply; irrigated labels do not
establish delivery; paddy additionally needs preparation/saturation, seepage and
percolation, bund/pond storage, drainage and standing-water targets.

Future rule promotion requires a separate versioned rule artifact, an independent
named agronomic review, original claims/locators, crop/cultivar and production
system, region and environmental/management applicability evidence, statistic and
calendar definitions, units, stages and actual offsets, exclusions, uncertainty,
review date and supersession policy. A catalog-owner acceptance must be explicit.
New tests/imports/lookups and source desk reviews cannot grant it. Review must
also cover local adjustments, field versus regional evidence and the consequence
of missing/conflicting inputs. Only after that process may a separate adapter
produce existing v0.3 `reviewed` rules; v2 remains permanently reference-only.
No accepted-rule registry is populated or automatically consumed in this milestone.

## Soil, photos, management and secondary layers

Laboratory measurements, farmer reports, surveys, SoilGrids predictions, HWSD maps,
land-surface products, photos and contradictory/unknown evidence are distinct.
The unchanged 7I WCS reader still rejects 7P's nodata-less raster. The new original
ISRIC WebDAV VRT metadata explicitly provides a nodata value, but this does **not**
establish the identity/encoding of that WCS response. No sentinel is injected and
no soil number is accepted. `evidence/soilgrids-vrt-metadata.json` and its original
response hash document the complementary route. No global raster archive was
downloaded. See `COVERAGE.md` for source access and acceptance gaps.

Existing authorized photos/history remain functional and separate. A photo cannot
establish chemistry, NPK, contamination or hydraulic capacity. Existing crop/fallow
history stays an attributed report; a calendar gap does not infer actual fallow,
legumes do not create nitrogen credits, and imagery does not reconstruct complete
history. Guided soil/land-use records and broader management UI remain P1 unless
explicitly documented as implemented in the final verification report.

Warnings/forecasts require authoritative geographic coverage and valid issue times.
No current warning is synthesized from historical POWER data. EPPO distribution
is not a diagnosed pest; FAOSTAT broad statistics are not farm prices or profit.
