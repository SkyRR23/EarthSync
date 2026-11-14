# Source manifest

Review date: 14 November 2026. Paths in the inventory table are relative to
`raw/original/data-pack/`. `{loc}` expands to all three location IDs below.
All files are individually hashed in [archive_inventory.json](archive_inventory.json).
All 46 CSV schemas, ranges and blanks are in
[audit_inventory.json](normalized/audit_inventory.json). A documented provider
unit does not establish the unit of a discarded original response.

## Locations

| ID | Latitude, longitude (WGS84 degrees) | Origin and spatial limitation |
| --- | --- | --- |
| hlegu | 16.87, 96.20 | Collector LOCATIONS and soil CSV; representative query point |
| bago | 17.33, 96.48 | Collector LOCATIONS and soil CSV; representative query point |
| magway | 20.15, 94.93 | Collector LOCATIONS and soil CSV; representative query point |
| us_nv_fallon | 39.50, -118.80 | Collector US_REF and elevation CSV; Nevada example only |

These are contributed query coordinates, not verified farm boundaries or native
pixel centres. Weather CSVs omit coordinates; association relies on the collector
and filenames, not retained original response geometry.

## Complete file-family inventory

| Files | Provider / product / classification | Actual coverage and spatial support | Disposition and limitation |
| --- | --- | --- | --- |
| `csv/power_daily_{loc}.csv` | NASA POWER; meteorology modeled, radiation satellite-derived/model-processed (not a homogeneous observed series) | 121 dates, 2026-07-15–11-12; meteorology nominal 0.5° latitude × 0.625° longitude; radiation has separate source support | Reference-only; no log entries, header units, lineage, fill declaration or time standard retained; variable blanks |
| `csv/power_monthly_{loc}.csv` | NASA POWER monthly, modeled meteorological context with separately sourced radiation | 120 year/month records, Jan 2016–Dec 2025; same parameter-specific grid caveat | Reference-only; rate precipitation, no daily completeness evidence; not backend input |
| `csv/power_climatology_{loc}.csv` | NASA POWER climatology; mixed parameter lineage as above | 10 parameters × 12 mislabeled slots; claimed 2001–2025 baseline unverified in original header | Blocked: January dropped, annual column included, numeric months shifted; no silent repair |
| `csv/current_{loc}.csv` | Open-Meteo weather-model current conditions, modeled | One local timestamp 2026-11-14T11:30; unknown actual model/grid resolution | Reference-only; column `observed_at_local` is misleading; retrieval/issue/UTC offset/interval absent |
| `csv/forecast16_{loc}.csv` | Open-Meteo Best Match request, forecast | 16 local dates, 2026-11-14–29; resolved model/grid unknown | Research fixture; cannot establish freshness, original units or model; last two days lack three soil variables |
| `csv/era5land_daily_{loc}.csv` | Open-Meteo archive, modeled reanalysis/model blend not proven ERA5-Land | 364 dates, 2025-11-14–2026-11-12; ERA5-Land nominal 0.1°, ERA5 0.25°, IFS 9 km alternatives | Reference-only: collector did not select `models=era5_land`; filename is not lineage evidence; no log/body |
| `csv/river_discharge_{loc}.csv` | Open-Meteo / GloFAS, forecast simulation | 16 dates, 2026-11-14–29; provider nominal v4 0.05° (~5 km), actual run unpinned | Reference-only: not measured farm water, inundation or a flood alert; river selection unverified, metadata/log absent |
| `csv/soilgrids_{loc}.csv` | ISRIC SoilGrids WMS mean estimates, modeled | 32 rows each: eight properties × four depths, 0–60 cm; nominal native 250 m; no observation date | Research fixture; conversions verified; quantiles, release, original HTML, native footprint absent |
| `csv/modis_ndvi_{loc}.csv`, `csv/modis_evi_{loc}.csv` | NASA MOD13Q1 via ORNL DAAC, observed satellite-derived indices | 46 starts per index, 2024-01-01–2025-12-19; nominal 16-day, 250 m | Research fixture; all expected starts, no blank values; QA/version/actual pixel support missing |
| `csv/modis_lst_day_{loc}.csv`, `csv/modis_lst_night_{loc}.csv` | NASA MOD11A2 via ORNL DAAC, observed satellite-derived surface temperature | 92 starts per series, 2024-01-01–2025-12-27; nominal 8-day, 1 km | Research fixture; large blank counts, QA absent; surface temperature does not replace T2M |
| `csv/modis_landcover_{loc}.csv` | NASA MCD12Q1 via ORNL DAAC, observed satellite-derived classification | Ten annual labels, 2015–2024; nominal 500 m | Reference-only: IGBP class is not farmer crop identity; QA/confidence/collection absent |
| `csv/terrain_grid_{loc}.csv` | Open-Meteo / Copernicus DEM, modeled elevation surface | 25 samples each; 0.02° grid spacing, offsets -2..2; provider GLO-90 nominal 90 m, 2021 release | Reference-only; spacing is ~2.2 km, not 90 m; acquisition time and vertical datum not retained |
| `csv/terrain_summary.csv` | Contribution-derived DEM summary, modeled | Three location summaries; elevation metres and slope percent | Reference-only; named km offsets are grid indices; fixed distance assumptions unsuitable as measured field slope |
| `csv/satellite_availability_cmr.csv` | NASA CMR discovery metadata; environmental data type unavailable | Ten product queries, 2025 interval; bbox 95.8,16.7,96.6,17.5 | Reference-only; excludes Magway; one returned granule does not establish all-date/all-field coverage |
| `csv/us_nv_ssurgo_components.csv` | USDA NRCS SSURGO map-unit interpretations, modeled/mapped context | Five component rows, Nevada query; map-unit spatial support, not a Myanmar grid | Reference-only US example; release/survey date/geometry absent; two hydrologic group and taxonomic fields blank |
| `csv/us_nv_elevation.csv` | USGS EPQS / 3DEP, modeled elevation surface | One Nevada elevation (m); native product resolution/date/vertical datum unretained | Reference-only US example |
| `tiles/{ndvi,lst_day,imerg,truecolor}_{loc}.jpg` | NASA GIBS browse visualizations of VIIRS, MODIS and IMERG | Twelve JPEGs; NDVI requested date Nov 2, LST Nov 1, IMERG Nov 12, truecolor Nov 14 2026; actual WMTS requests in log | Reference-only imagery; no quantitative samples or QA can be recovered from colours; image type is browse visualization, not a numeric observation fixture |
| `README.md`, `api.txt` | Contributor narrative/reference catalog | No environmental measurements beyond embedded examples | Reference-only; `[WORKS]` is not a validated integration status; crop/soil/anomaly proposals unapproved |
| `scripts/fetch_sources.py` | Contributor collector | Reviewed statically, not run; date-relative requests and mutable default products | Preserved only; see review in QUALITY_REPORT |
| `_meta/fetch_log.csv` | Contributor retrieval records | 522 rows, 2026-11-14T05:15:57Z–06:41:28Z | Partial provenance, not source measurements; 441 `ok`, 81 `failed`; no response hashes |

No crop-reference catalog, field-context JSON, `build_data.py`, laboratory
measurements, farmer reports, uncertainty quantiles or MODIS QA files exist in
the archive. SMAP, raw IMERG, ECOSTRESS, GEDI, VIIRS quantitative series,
Landsat, NLDAS/GLDAS and other APIs in `api.txt` are discovery/reference ideas,
not supplied measurements. CMR documents eight matching results and two empty
results for its box; it does not establish access rights or local validity.

## Units and transformations

### POWER — catalog units verified, original response assertions unavailable

The audit separately captured official AG parameter metadata for `daily`,
`monthly` and `climatology` in [provider_evidence](provider_evidence/).

| Parameter / contributed column | Catalog unit | Interpretation / permitted future conversion |
| --- | --- | --- |
| T2M, T2M_MAX, T2M_MIN / `*_c` | C | Celsius; MAX/MIN are period extremes, not automatically mean daily maxima/minima |
| PRECTOTCORR / `prectotcorr_mm_day` | mm/day | Rate; daily × one day gives mm; a monthly rate is not itself a monthly total |
| RH2M / `rh2m_pct` | % | Relative humidity |
| WS2M / `ws2m_m_s` | m/s | Wind at 2 m, not forecast wind at 10 m |
| WD2M / `wd2m_deg` | Degrees | Wind direction; do not average as ordinary linear numbers |
| ALLSKY_SFC_SW_DWN / `*_mj_m2_day` | MJ/m²/day | AG radiation energy convention; separate lineage/grid from meteorology |
| GWETTOP, GWETROOT / `*_frac` | 1 | Modeled wetness, not interchangeable with volumetric m³/m³ soil moisture |

No POWER series is normalized into monthly engine input here. Provider catalog
agreement cannot restore original time standard, missing-day evidence or source
headers. For future monthly-rate conversion, require verified product semantics
and full-month coverage before multiplying by Gregorian calendar days.

### Soil — all 96 contributed conversions checked

| Property | Original CSV unit | Fixture operation | Fixture unit |
| --- | --- | --- | --- |
| phh2o | pH*10 | × 0.1 | pH |
| clay, sand, silt | g/kg | × 0.1 | % by mass |
| soc | dg/kg | × 0.1 | g/kg |
| nitrogen | cg/kg | × 0.01 | g/kg |
| cec | mmol(c)/kg | identity | mmol(c)/kg |
| bdod | cg/cm³ | × 0.01 | g/cm³ |

Provider conversion/depth/quantile semantics: [ISRIC layers](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html).
Depths supplied: 0–5, 5–15, 15–30, 30–60 cm; 60–100 and 100–200 cm absent.
Q05/Q95 define a 90% prediction interval, not a fabricated accuracy score.
All uncertainty remains null. CEC can alternatively divide by 10 to cmol(c)/kg;
the fixture intentionally retains its original unit. `value_si` is not uniformly
SI: pH and percent are convenience units. These estimates do not establish
farm drainage, crop suitability, available nutrient supply or a sampled soil profile.

### Vegetation and LST

NDVI/EVI integer codes × 0.0001 give dimensionless values; nominal valid raw
range -2000..10000, fill -3000. LST integer codes × 0.02 give kelvin; subtract
273.15 for Celsius, only after missing/range checks. Check actual product
metadata before using these conventions on a different collection/representation.
Scale factors may already be applied by an intermediary; never scale twice.

The [NASA MOD13 specification](https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/MOD13Q1)
and [NASA MOD11A2 specification](https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/MOD11A2)
were reviewed alongside the serving platform's
[MOD13Q1 catalog](https://developers.google.com/earth-engine/datasets/catalog/MODIS_061_MOD13Q1)
and [MOD11A2 catalog](https://developers.google.com/earth-engine/datasets/catalog/MODIS_061_MOD11A2).
MOD11A2 averages available daily surface retrievals, with composite QA; this
does not prove eight daily samples. The year-end composite is shorter than the
nominal cadence. No pixel-level numeric uncertainty is inferred from QA codes.

### Open-Meteo and reference sources

[Forecast documentation](https://open-meteo.com/en/docs) supports Celsius
temperatures, daily precipitation/ET0 in mm, relative humidity/probability in %, wind
in km/h by default, daily solar energy in MJ/m², soil moisture in m³/m³ and
soil temperature in Celsius. These match the collector's requested variables
and CSV aliases. Original `daily_units`/`current_units` are absent: their exact
returned units are **unverified**, and the forecast fixtures say so. Current
precipitation's interval was discarded; do not interpret it as a daily total.

[Historical API](https://open-meteo.com/en/docs/historical-weather-api) documents
multiple archive models; an `era5land` filename does not select one.
[Flood API](https://open-meteo.com/en/docs/flood-api) reports simulated discharge
in m³/s, not water depth or rainfall; the selected river may be unrepresentative.
[Elevation API](https://open-meteo.com/en/docs/elevation-api) identifies Copernicus
DEM GLO-90 and elevation in metres. SSURGO components are map-unit attributes
and percentages; [NRCS documentation](https://www.nrcs.usda.gov/resources/data-and-reports/gridded-soil-survey-geographic-gssurgo-database)
does not turn the Nevada example into Myanmar evidence. These reference-only
sources need product-specific metadata validation before any future adapter.

## Provenance and retrieval status

Soil: 288 records (276 `ok`, 12 failed Ksat attempts). Successes record zero
response bytes by collector design; repeated requests cannot be mapped uniquely
to final CSV values without original HTML. MODIS: 178 records (136 `ok`, 42
failed oversized requests). Log targets use band/product names, not output
location filenames; fixture links match coordinates/product/band in request URLs.
GIBS: 39 tile attempts (12 `ok`, 27 failed), plus two capabilities records.
CMR: ten `ok` searches; elevation: three; USDA and USGS: one each.
There are **zero** NASA POWER, weather forecast/current/archive or flood log
records, despite their CSV files and README's claim that every number is logged.
`api.txt` request examples are not retrieval records.

Original transport attempts are not independently replayed. The log collapses
internal retries and uses `http_status=-` for failures; reported 400 responses
survive only in notes. No successful request alone certifies scientific validity.
Documentation requests to LP DAAC product pages and Earthdata catalog pages
returned 403 in the web reader; NASA LAADS specifications and platform catalogs
were readable. The old POWER `/methodology/meteorology/` URL returned 404;
use the [current meteorological methodology](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/).
The USGS 3DEP overview timed out in the web reader; native metadata remains unverified.

## Licensing and attribution

| Source | Requirements / status before reuse |
| --- | --- |
| ISRIC SoilGrids | [CC BY 4.0](https://isric.org/explore/soilgrids/): credit ISRIC, link license/product, identify conversions and subset; retain release and access date when known |
| Open-Meteo | [Terms](https://open-meteo.com/en/terms): data CC BY 4.0, attribute Open-Meteo and relevant underlying provider; free API access is restricted to noncommercial use independently of the data license. Future production access needs the appropriate service plan |
| Copernicus DEM via Open-Meteo | [Elevation citation guidance](https://open-meteo.com/en/docs/elevation-api): credit Copernicus and Open-Meteo, cite DOI 10.5270/ESA-c5d3d65; retain applicable GLO-90 terms before downstream publication |
| MODIS / ORNL DAAC | NASA data are openly reusable; cite the exact product and collection plus [ORNL service](https://modis.ornl.gov/data/modis_webservice.html), DOI 10.3334/ORNLDAAC/1600, per [citation guidance](https://modis.ornl.gov/citation.html). Candidate product DOIs 10.5067/MODIS/MOD13Q1.061 and 10.5067/MODIS/MOD11A2.061 require verification of the contributed subset collection |
| NASA POWER | Credit NASA LaRC POWER and underlying products; retain query, access time and parameter-specific lineage. Follow [POWER references](https://power.larc.nasa.gov/docs/references/) and original response acknowledgment when recovered; absent original notices are not inferred |
| NASA GIBS | [GIBS documentation](https://nasa-gibs.github.io/gibs-api-docs/) requests acknowledgment of NASA GIBS/ESDIS; retain layer/product/date and underlying source attribution |
| CMR | Discovery metadata; cite NASA CMR and original product metadata; search results do not grant rights to undownloaded datasets |
| USDA NRCS / USGS | Preserve agency/product/access-date attribution; product-specific notices/release metadata were not contributed. US-only examples remain reference-only |
| Contributor README, api.txt and collector | No explicit license file in the archive. Preserved as the user-supplied research contribution; no blanket relicensing of original prose or code is asserted |

Attribution suggested for derived soil fixtures: “ISRIC SoilGrids modeled
properties, queried at the listed points and depths via ISRIC WMS; units
converted as documented by EarthSync; CC BY 4.0; uncertainty not supplied.”
For archived forecasts: “Weather data by Open-Meteo; converted to an EarthSync
research fixture; issue/retrieval/model metadata not supplied; not live weather.”
These are source acknowledgments, not claims of provider endorsement.
