# Scientific acceptance boundaries

## NASA daily extension and GEOS-IT

The old monthly MERRA-2 contract is untouched. PR #12's GEOS-IT proposal was read;
it requires distinct attribution and independent validation. GEOSIT is **not**
enabled here, including mixed header/chunk cases. The new daily adapter requests
one variable at a time. Exact accepted headers are documented in
`nasa-source-review.json`, with hashes of the live official methodology/catalog
responses and real captures. NASA assigns Tmin/Tmax to POWER processing of hourly
MERRA-2 temperatures; its daily precipitation parameter is source-derived. This
specific documented transformation chain is retained rather than labeled as
unknown temporal mixing. Other source lists and API versions fail closed.

Original units (`C`, `mm/day`), headers, parameter metadata, geometry, messages and
response hashes survive. Daily precipitation remains a daily rate in the engine;
no partial-month totals or monthly-derived extrema are substituted. Leap-day,
missing-day and cross-year calendar handling uses explicit dates. LST is a solar
swath convention, not a civil farm timezone or confirmed crop growing calendar.
Completeness is coverage, not local accuracy. Regional model records do not become
point measurements because they are associated with a confirmed farm.

Sources: [NASA meteorological methods](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/),
[NASA daily API](https://power.larc.nasa.gov/docs/services/api/temporal/daily/),
[live parameter catalog](https://power.larc.nasa.gov/api/system/manager/parameters?community=AG&temporal=daily).

## ET0 and GDD

No ET0 is calculated or represented as an available measurement. Reference
[FAO-56 Penman–Monteith inputs](https://www.fao.org/4/x0490e/x0490e06.htm)
require validated radiation, temperature, humidity/vapour pressure, wind with
height conventions and pressure/elevation/time alignment. Land evaporation or
transpiration variables are not automatically reference ET0. A reviewed daily
input/method pipeline and applicable Kc stages remain absent. Monthly mean T2M
and rainfall cannot support daily extrema, ET0 or GDD. Rust remains authoritative
for any future sourced-base GDD and aligned ETc calculations; Python duplicates
neither method. Current catalog profiles cannot enable these rules.

## Soil

[ISRIC's REST announcement](https://docs.isric.org/globaldata/soilgrids/index.html)
reports a paused beta REST service. The independent
[WCS protocol](https://docs.isric.org/globaldata/soilgrids/wcs.html) and
[property/unit documentation](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html)
support a focused pH probe. It validates coverage, 0–5 cm interval, native 250 m
raster/CRS, no-data and pH ×10 conversion. A live descriptor+raster pair could not
be retrieved through this environment's proxy. Output stays reference-only;
quantiles and exact release are explicit gaps. Do not substitute WMS color values,
claim a laboratory sample, infer drainage, or manufacture unavailable soil values.
PR #17 retains broader REST properties/quantiles without being promoted here.
USDA and Australian endpoints were proxy-blocked; no working adapters claimed.

## Optical and SAR

[HLS specifications](https://hls.gsfc.nasa.gov/data-products/) and
[the HLS v2 guide](https://lpdaac.usgs.gov/documents/1698/HLS_User_Guide_V2.pdf)
are the native QA/scale reference. Local routines require co-registered 30 m
red/NIR/Fmask GeoTIFFs and exact product/band/version metadata. Conservative QA
excludes cirrus, cloud, adjacency, shadow, snow, water, high aerosol, fill,
negative reflectance and zero denominator; its policy remains in output. Only
wholly contained field pixels contribute. Valid support coverage is reported;
there is no arbitrary minimum acreage, health threshold, disease diagnosis or
field-wide average for unsupported polygons. Large windows are rejected by a
resource cap, not a scientific crop threshold.

[OPERA/ASF's product guide](https://hyp3-docs.asf.alaska.edu/guides/opera_rtc_product_guide/)
describes gamma0 power at 30 m spacing. This PR only processes trusted local
operator manifests and arrays, retaining acquisition, polarization, orbit,
burst/static geometry and processing lineage. Native mask acceptance requires an
explicit reviewed convention. Summary differences remain unavailable without
common valid native pixels. Radar brightness is not direct moisture, flooding,
plant health or disease. Source access/metadata are unverified; no new live OPERA
acquisitions or interpretation methods are claimed.

## Pilots and crop references

The 12 raw NASA pilot captures use explicitly approximate public regional query
points for Story County, Tribune, Stuttgart and Griffith/Riverina. All returned
29 days for February 2024. They are not farm centroids, boundaries, extension
field trials, forecasts or ground truth. PR #15 retains institutional sources and
partial pilot reference coverage. No new local scientific review of requirements,
planting/harvest calendars, irrigation availability, cultivar or weather skill
was performed. Advisory planting guidance is not a hard biological constraint;
soil establishment temperature is not air temperature. Fallow is an explicit
management assertion, not an inferred empty calendar gap.

The API accepts explicit plan periods, keeps farmer-reported history unreviewed,
and lets Rust identify deterministic sequential schedule conflicts. All positive
crop recommendation eligibility remains false. A regional research pilot ID does
not establish geographic applicability for a real farm. Synthetic QA rasters,
unit mutations and sample farm confirmations in tests remain software test data,
separate from exact captured provider responses.
