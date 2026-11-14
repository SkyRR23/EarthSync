# Historical versus current issue matrix

Pins: final 7H `a7c33cc6`, 7I `b578a6df`, 7L `bd8d245b`, PR #11
`a85e2dd4`, original v0.3 `6f7f8107`. "Historical-only" below refers only to
the available PR #11 pack or named earlier implementation. It does not establish
anything about the inaccessible `nasa_space_challenges.zip`.

| # | Concern | Historical evidence reviewed | Final 7H / v0.3 / 7I disposition |
| --- | --- | --- | --- |
| 1 | January/February misalignment | PR #11 `power_climatology_*.csv`: ordinal 1 is FEB, JAN absent | Historical-only for that pack. 7H aggregates named daily dates; Jan/Feb leap test passes. 7I uses daily dates. |
| 2 | Annual aggregate in monthly slot | PR #11 climatology ordinal 12 is ANN; collector slices climatology like monthly CSV | Historical-only. 7H/J03 now rejects ANN in daily records; no positional climatology importer used. |
| 3 | 120/365-day coverage assumptions | PR #11 daily POWER has 121 inclusive rows; ERA5 file has 364 rows, not 365. Names/comments do not prove valid values | Historical pack defect. 7H uses actual 28/29/30/31-day calendars; v0.3 iterates inclusive Gregorian days; 7I enumerates requested dates. |
| 4 | MERRA-2 called observed | New archive claim not yet independently reproduced; PR #11 flattened CSV lacks typed provenance | Current adapters explicitly modeled, reject GEOSIT drift. No observed relabeling found in current NASA path. Generic caller provenance cannot prove actual lineage. |
| 5 | Missing original provider metadata | PR #11 lacks original POWER/Open-Meteo bodies and retrieval logs for those families | 7H retains headers, units, query, geometry; exact response hash missing (J04, fixed). 7I retains hashes and metadata. No fabricated recovery of past captures. |
| 6 | Missing/mismatched farm geometry | PR #11 many CSVs lack provider footprint. Current 7H unchecked geometry reproduced | J01 fixed for default NASA path. J05 fixed for regional history becoming field occupancy. 7I daily geometry/ownership gates already present. |
| 7 | SoilGrids WMS pixel/depth uncertainty | PR #11 center map pixel over a 0.5-degree box; native footprint/quantiles absent; four depths only | Research only. 7H defaults unavailable; 7I WCS probe is not accepted farm soil evidence. No inferred root-zone or drainage measurement. |
| 8 | MODIS LST fill/QA | PR #11 collector discards 65535 as fill; 206/552 retained values missing; no QC | Historical-only importer defect, with irrecoverable discarded raw codes. Current live LST ingestion absent. Skin LST never substituted for daily air Tmin/Tmax. |
| 9 | NDVI/EVI QA | PR #11 46 starts per index/location but no VI QA/cloud/pixel reliability | Still blocks reuse of pack; current HLS/optical QA foundations do not validate these MODIS series. No live vegetation diagnosis accepted. |
| 10 | Incorrect CMR bbox | PR #11 95.8,16.7,96.6,17.5 excludes Magway 94.93 E,20.15 N; page_size=1 | Historical-only bounding-box claim. 7I discovery constructs farm queries; catalog availability is distinct from usable field pixels. |
| 11 | Forecast without trusted model-run ID | PR #11 forecast snapshots lack original run/time identity | Live gates remain blocked/unavailable. Generic v0.3 has issue date only: explicit future contract limitation, not independently verified live forecasting. |
| 12 | Temperature statistic mismatch | PR #11 monthly extrema and LST cannot substitute for mean daily air extremes | Current 7H uses T2M daily mean for monthly means; v0.3 temperature means every supplied Tmin/Tmax within bounds, GDD uses uncapped daily midpoint. Catalog soil-temperature guidance is not mapped into air-temperature rules. |
| 13 | Unsupported crop rankings/weights | Existing OpenFarm research documents external 40/25/20/15 weights; contributed archive not yet reviewed | No weighted engine imported into v0.3; unranked scenarios and persistent uncertainty. No archive engine adoption. |
| 14 | Unverified rules produce positive suitability | Not reproduced in available repository implementation; new archive pending | Current catalog projection is reference-only with empty rules and no candidates; tests reject reference/unreviewed/synthetic promotion. Review booleans alone are not scientific acceptance. |
| 15 | Hard-coded irrigation credit | New archive pending; no such credit found in current v0.3 | Availability bool does not fill rainfall or ET0 gaps or prove adequacy. Regression covers this boundary. |
| 16 | Rotation order lost/reordered | Earlier Flutter fix `c8c15fe` preserves engine order | Historical correction retained. Current Rust preserves supplied plans; reversed/overlapping sequences yield conflict under explicit sequential-field assertion. J05 concerns evidence identity, not order. |
| 17 | Unsourced nitrogen/pest benefits | New archive pending; no current quantified benefit method found | v0.3 supplies no nitrogen/pest benefit claim. Family/taxon identity alone is not a benefit or restriction. |
| 18 | Finance inferred from market-use counts | New archive pending; not reproduced in available current code | No current v0.3 financial calculation or accepted financial crop rule. No historical claim can be confirmed without that source. |
| 19 | Rainfall rates/totals | PR #11 monthly POWER retains mm/day; current precip interval absent | 7H sums daily rate times one day, complete months only; v0.3 sums complete daily mm/day records over growing period. No annual-to-season interpolation or effective-rain assumption. |
| 20 | Missing ET0/stage Kc | PR #11 flattened forecast ET0 has incomplete provenance; no accepted local crop Kc | Actual live ET0 remains missing in 7I. v0.3 requires complete aligned ET0 plus method and complete sourced Kc stages. ETc arithmetic is not irrigation sufficiency. |

Current claims above are based on static paths and deterministic tests, not field
trials. There is no blanket assertion that all historical defects were present,
or that all possible modern scientific defects have been eliminated.
