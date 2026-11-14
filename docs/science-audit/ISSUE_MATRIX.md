# Historical versus current issue matrix

Pins: final 7H `a7c33cc6`, 7I `b578a6df`, 7L `bd8d245b`, original v0.3
`6f7f8107`, PR #11 `a85e2dd4`. The contributed ZIP is identified by its verified
SHA-256, not assumed to be a repository version. All 20 concerns were checked.

| # | Concern | Contributed/historical result | Current final 7H / v0.3 / 7I result |
| --- | --- | --- | --- |
| 1 | Jan/Feb misalignment | All 360 flattened climatology rows shift FEB to ordinal 1 | Historical-only; daily date-based Jan/Feb leap regression passes. |
| 2 | Annual values in monthly slots | ANN ordinal 12 in flattened climatology; old Rust accepts a mutated month-13 slot. Separate JSON builder correctly skips annual month 13 | Modern date/unit validators reject unsupported slots. No positional climatology importer adopted. |
| 3 | 120/365-day assumptions | 121/364 rows; builder averages nine of ten January samples while implying completeness | Modern actual calendars/missingness retained; research normal validator requires complete year-month coverage. |
| 4 | MERRA-2 called observed | Confirmed in builder, three contexts and analysis status | Current NASA adapters modeled, reject GEOSIT drift. Generic caller provenance is not independent authentication. |
| 5 | Original provider metadata | Six JSON bodies plus URL sidecars now exist; original fetch receipts still absent, many CSV families lack bodies | 7H retains metadata; J04 adds response hash. 7I already retains hashes. No invented retrieval recovery. |
| 6 | Farm/climate geometry | Old engine accepts different-continent farm with Hlegu context | J01 fixes unchecked 7H provider point; J05 fixes regional history as field occupancy. J06 provides tested 7I coordinate-precision patch. |
| 7 | SoilGrids WMS pixel/depth | Map pixel is not native footprint; four depths/means, no quantiles or field sampling evidence | Current defaults unavailable/reference-only. No drainage/root-zone measurement inferred. |
| 8 | MODIS LST fill/QA | Collector discards 65535 universally; 206/552 values missing, no QC | Historical importer rejected. No accepted current live LST or skin-LST to air-extreme substitution. |
| 9 | NDVI/EVI QA | Complete composite starts but absent VI QA/cloud/reliability; 18% anomaly sample unsupported | Pack reuse blocked for diagnoses/anomalies. HLS foundations do not validate these MODIS pixels. |
| 10 | CMR bbox | 95.8,16.7,96.6,17.5 excludes Magway; one catalog result does not prove coverage | Historical query defect. 7I discovery uses farm context; discovery remains distinct from usable pixels. |
| 11 | Forecast identity | Snapshots lack original run/issue/model-response identity | Live adapters unavailable/blocked. Generic v0.3 issue date is not trusted run identity; preserve source gates. |
| 12 | Temperature statistic | Monthly T2M_MAX/MIN used as mean daily extrema; ECOCROP bounds lack executable statistic/stage applicability | Modern daily Tmin/Tmax and T2M means retained. No soil guidance mapped into air-temperature rules. |
| 13 | Ranking/weights | Six-axis heuristic, team weights, missing axes dropped, unsupported ranking | No weighted engine imported. Modern scenarios unranked, no calibrated score claimed. |
| 14 | Unverified positive support | Warning does not block Supported; six medium-confidence profiles counted sourced from numeric completeness | Current reference-only catalog ineligible, no rules/candidates. New Myanmar fixture likewise has zero executable rules. |
| 15 | Irrigation credits | Fixed 120/350 mm; zero-rain synthetic case still Supported | Current availability does not prove adequacy or fill missing rainfall/ET0; regression passes. |
| 16 | Rotation sequencing | Repeated baseline removed; reverse alternatives collapsed; incompatible baseline planting month replaced | Modern supplied order/dates and explicit sequence checks retained. Old month substitution not imported. |
| 17 | N/pest benefits | Missing legume N rate gets 0.6; family diversity becomes pest benefit without host/trial evidence | No automatic quantified N/pest benefit in v0.3. Family identity alone is not a transition rule. |
| 18 | Market counts to finance | Income score 2/3 from two use labels without prices, costs, yield or demand | No modern financial calculation accepted. Historical score is an unsupported proxy, not a currency/profit amount. |
| 19 | Rain rate versus total | Monthly CSV retains mm/day. JSON builder multiplies by days but uses fixed February and incomplete averaging | Modern daily sums use exact dates; research conversion uses each year's calendar. No effective-rain or annual-to-season inference. |
| 20 | ET0 / stage Kc | Hargreaves code exists with correct radiation conversion, but monthly-extreme input statistics/local verification inadequate. Team ETc has no stage Kc calculation | Live ET0 missing in 7I. v0.3 requires aligned complete ET0/method and Kc stages; ETc is not irrigation sufficiency. |

Additional archive defects: its advertised equal-five-year comparison uses the
ten-year mean against the first five years (268.7 vs declared 537.2 mm Hlegu
difference); negative rain is accepted; a public annual aggregate accepts a
single month. See [historical reproductions](ARCHIVE_FINDINGS.md).

No historical defect was presumed present in modern code. These software and
source checks do not establish local agronomic validity.
