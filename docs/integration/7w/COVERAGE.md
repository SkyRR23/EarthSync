# Soil, satellite, terrain and agricultural context coverage

Only POWER weather used in the tested Rust computation is **NUMERICALLY
INTEGRATED** in 7W. Metadata, reachable documentation, inherited synthetic QA
tests and visual tiles do not count. No large global raster archive was fetched.
7P's inventories remain unchanged; this report records the consumer disposition.
Dates below describe products, not current field conditions or forecasts.

| Source / provider and version | Coverage / resolution / temporal support / units | Rights | Actual access and QA disposition / limitations |
|---|---|---|---|
| NASA POWER API v2.10.3; MERRA-2 meteorology and SYN1deg solar, exact captures pinned by hash | Global regional point context, 0.5° × 0.625° meteorology and 1° radiation; daily historical LST, accepted water period from 2001; C, mm/day, m/s, kPa, MJ/m²/day | NASA open data; retain NASA POWER and underlying-product attribution | **NUMERICALLY INTEGRATED** for the accepted response contract: separate parameter requests, source/unit/geometry/date/fill guards, actual Rust calculation and persisted results. GEOSIT/SRB/FLASHFlux changes remain unavailable for this method. See SCIENCE.md and actual receipts. |
| [NASA GPM IMERG V07 family](https://gpm.nasa.gov/data/imerg) | Near-global precipitation; typical 0.1° / half-hourly, daily and monthly products have distinct time bases; rate versus accumulation must be pinned | NASA open science data; collection attribution/terms must be retained | Documentation/reference inventory only. No local granule fetched/validated/used. Early/Late/Final latency, QA and polar support must be selected. Not an alternative rain total in this app. |
| [NASA SMAP](https://smap.jpl.nasa.gov/data/) L2/L3 retrievals, L4 modeled/assimilated products | Product-dependent global EASE grids, common 36 km or 9 km posting; 2015 onward; m³/m³ with explicit depth and interval | NASA/NSIDC collection-specific open-data attribution | No numerical fetch. Native QA must cover frozen soil, water, retrieval flags and interference. A regional modeled root-zone pixel is not a field sensor or a soil test. |
| [NASA HLS](https://hls.gsfc.nasa.gov/data-products/) L30/S30 v2.0 | Land scenes, 30 m; acquisition dates and tile footprints; scaled surface reflectance | NASA HLS open data; retain product citation | Inherited 7I local-reader/Fmask tests; 7P CMR collection metadata succeeded. No new accepted numerical pixels. Red/NIR/Fmask registration, cloud/shadow/water masks and field coverage remain necessary. |
| [NASA MODIS](https://www.earthdata.nasa.gov/data/catalog/lpcloud-mod13q1-061) MOD13Q1.061 candidate; MOD11 temperature separate | MOD13 example 250 m / 16-day NDVI/EVI composites, dimensionless scaled values; temperature products have other resolutions/time support and Kelvin units | NASA collection attribution | No new granules or QA accepted. 7P recorded documentation access failures. Vegetation index does not establish nutrients, disease, moisture or yield; surface skin temperature is not 2 m air temperature. |
| [NASA OPERA](https://www.jpl.nasa.gov/go/opera/products/) RTC-S1, DSWx, DIST families | Product-specific global/regional availability, commonly 30 m posting; acquisition/composite/orbit support; backscatter or classes | NASA product-specific open-data citation | Inherited local radar reader tests only. No accepted remote granules. Pin product/version/orbit/polarization/native masks. Radar brightness is not direct soil moisture; detection classes need product-specific validation. |
| [NASA GIBS](https://nasa-gibs.github.io/gibs-api-docs/) layer-specific WMTS/WMS | Dated visual imagery; layer/projection/zoom-dependent display resolution; image colors, no accepted numeric science units | Provider/layer-specific visualization attribution | Existing dated visual pathway retained. Visual context only; no display-color-to-NDVI or soil-moisture decoding. Tile access is not numerical integration. |
| [NASA CMR/Earthdata](https://cmr.earthdata.nasa.gov/search/site/docs/search/api.html) collection/granule metadata | Global discovery footprints and date extents; no sampled-pixel unit or resolution implied by metadata | NASA metadata access and source collection terms | 7P's real collection discovery succeeded; existing bounded discovery reader retained. Authentication, authorized asset retrieval and native scientific QA remain separate. |
| [NASADEM HGT.001](https://www.earthdata.nasa.gov/data/catalog/lpcloud-nasadem-hgt-001), NASA JPL/LP DAAC | 60°N–56°S land; 1 arc-second spacing, 1° tiles; historical SRTM-derived terrain; elevation metres with vertical datum to verify | NASA collection citation/terms | Official catalog investigated, no local elevation raster fetched. Native nodata, vertical datum, source-quality flags and bounded extraction required. POWER model elevation is not relabeled NASADEM or surveyed farm slope/drainage. |
| [ESA WorldCover](https://esa-worldcover.org/en/data-access), 2020 v100 / 2021 v200 | Global 10 m categorical land-cover maps for the named year | CC BY 4.0; ESA WorldCover/Copernicus attribution | No numeric/category pixels retrieved. Version-dependent class legend and validation masks required. Land cover does not establish crop identity or complete land-use history. Different algorithms complicate direct year-to-year change attribution. |
| [Google/WRI Dynamic World V1](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_DYNAMICWORLD_V1) | Sentinel-2-based 10 m land-cover probabilities/labels from 2015; nine classes, probabilities 0–1; per-image model version/acquisition | CC BY 4.0; Earth Engine access/usage conditions separate | Official catalog investigated, no authenticated bounded query or pixels used. Cloud/quality masks, model version and temporal aggregation needed. Crop class is not a named crop cycle or complete history. |
| [FAO/IIASA GAEZ v5](https://data.fao.org/catalog/dataset/gaez-v5-master-config) | Global modeled crop/land-utilization contexts; general 5 arc-minute and selected 30 arc-second products; historical 1981–2000 / 2001–2020 and named CMIP6 future periods; product-specific units | Master config CC BY 4.0; individual raster/third-party rights still require checking | 7P already imports exact official configuration metadata. No numerical spatial extract accepted. Legend, scenario, crop type, management, irrigation regime, units/scale/nodata and native grid need acceptance. Potential yield is not predicted farm yield. |
| [ISRIC SoilGrids](https://docs.isric.org/globaldata/soilgrids/) 250 m 2.0 family / mutable latest alias | Global modeled 250 m interrupted-Goode-Homolosine predictions; 0–5, 5–15, 15–30, 30–60, 60–100, 100–200 cm; pH, SOC, fractions and density have distinct scale factors | CC BY 4.0, ISRIC citation | 7P WCS raster remains rejected because its nodata metadata are absent. 7W fetched the original WebDAV pH 0–5 cm mean VRT metadata: explicit nodata/CRS/transform are present, but no sample or matching WCS product identity is established. Release, quantiles, effective dates and bounded pixel acceptance remain unresolved. **Not numerical integration.** |
| [FAO/IIASA HWSD](https://www.fao.org/land-water/resources/tools/databases/hwsd/en) v2.0; [v2.2 lead](https://www.fao.org/agroinformatics/training-and-resources/data-sets/data-set-detail/new-version-of-the-harmonized-world-soil-database/en) | Global regional soil inventory, approximately 1 km / 30 arc-seconds; seven layers to 200 cm in the v2 family; mapped units linked to soil attribute tables | Dataset-specific FAO attribution/redistribution terms need confirmation before bundling chosen release | Official descriptions investigated; no bounded raster + component-table sample accepted. Harmonized map units are complementary to SoilGrids predictions and cannot replace field laboratory measurements. Do not silently substitute v2.2 for a pinned v2.0 source. |
| [FAO AQUAMAPS/AQUASTAT](https://www.fao.org/aquastat/en/geospatial-information/aquamaps/) | Regional/global water resources and agricultural water-management layers; native resolution, date window and units vary per resource | FAO and external-provider layer-specific conditions | Official descriptions investigated; no numerical resource selected/used. Country/basin water statistics do not establish a farmer's legal allocation, delivery reliability or irrigation efficiency. |
| [Copernicus CEMS GloFAS](https://confluence.ecmwf.int/spaces/CEMS/pages/265028796/Latest+operational+GloFAS+release), operational v4.5 lead | Global modeled river context, 0.05°; time-stamped forecasts/reanalysis/hazard products differ; discharge m³/s or product-specific probabilities/classes | Copernicus/ECMWF product-specific license and acknowledgment | Official release descriptions investigated; no issued forecast or numerical extract used. Native basin/grid support, issue/valid times, ensemble/calibration and flood thresholds required. Hazard is not confirmed field inundation. A pre-operational v5 description is not silently treated as an accepted operational version. |

## Soil evidence semantics and complementary access

Existing evidence sidecars retain native CRS, geometry, resolution, property,
depth, original/normalized units, method, retrieval/effective dates and limitations
when accepted. Regional soil predictions/maps remain modeled context. A farmer
report or photo does not become a laboratory measurement. The current milestone
does not execute new soil constraints because neither accepted field measurements
nor independently applicable crop rules are available.

7P's original diagnostic is
`data/crop-knowledge/v2/evidence/soil-wcs-rejected-receipt.json` and the unchanged
reader is `server/earthsync/platform_v1/providers/soil_wcs.py`. The new VRT
metadata response was 3,524,139 bytes; only selected metadata and its original
hash/URL/retrieval receipt are committed. The VRT's `-32768` nodata belongs to
that named WebDAV asset. It is **not assigned** to the WCS TIFF. Native depth
and per-property scaling are documented in 7P; chemistry, quantile uncertainty,
release identity and sample support cannot be filled from plausible values.

## Secondary context and nonclaims

- Official national meteorological services/WMO warnings: a globally appropriate
  issuing authority, geographical support, issue/valid times and withdrawal state
  must be verified. No live warnings or forecasts are integrated.
- Drought/flood advisories: distinguish historical indicators, forecasts, hazard
  layers and verified observed events. No confirmed local event is inferred here.
- [EPPO Global Database](https://www.eppo.int/RESOURCES/eppo_databases/global_database):
  authoritative pest/host/distribution references; data-service permissions and
  exact status dates need review. No diagnosed infestation or automatic pesticide
  advice is produced from distribution records.
- [FAOSTAT](https://www.fao.org/faostat/en/): broad official agricultural statistics,
  with dataset/year/unit and access terms to pin. No farmer profit calculation;
  relevant prices, input costs and justified yield estimates are absent.
- Farmer priorities, labor, equipment, delivered water, field soil tests and
  management records remain necessary inputs. Existing farmer crop/fallow history
  and planning notes retain attribution. A former road/construction site requires
  compaction/contamination investigation; the app has no basis to certify it safe
  for food production. No nitrogen credit or complete imagery-derived history is
  assumed.

The listed unintegrated providers are P1/P2 follow-ups, not completed numerical
features. They do not block the working historical POWER/reference Web workflow.
