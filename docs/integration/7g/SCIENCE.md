# 7G source and processing contract

No new agricultural rule, crop ranking, yield, irrigation quantity, crop
suitability threshold or independently verified field measurement is introduced.
Rust v0.3 and all 7W/7P/7V restrictions remain authoritative.

## Field boundaries and map licensing

Coordinates are EPSG:4326 longitude/latitude in GeoJSON. The device model stores
an unclosed immutable exterior vertex list and writes a closed ring; the backend
reuses its existing Shapely topology and point-association checks. The additional
client checks reject repeated edges, zero area, self-intersections and longitude
spans >180°. Unsupported crossings are rejected, never wrapped or fabricated.

Displayed area is the absolute spherical trapezoid integral
`R²/2 × Σ Δlongitude × (sin(latitude_i)+sin(latitude_i+1))`, radians,
mean Earth radius R=6371008.8 m. It is an approximate spherical field area, not
an ellipsoidal geodesic or surveyed legal area. For small fields ellipsoid
variation is approximately within 1%; long edges, large regions and high-latitude
shapes need a dedicated geodesic/survey workflow. The UI labels it approximate.
Synthetic tests cover an equatorial 0.001° square, reversed winding, topology,
point inclusion and persistence. An area estimate does not establish ownership.

Reuse flutter_map 8.3.2 (BSD-3-Clause) and latlong2 0.10.1 (Apache-2.0), already
locked by 7W; no map dependency or lockfile changes. Their license files were
inspected in the resolved packages. OSM data/attribution are ODbL; public raster
tile service usage policy is separate and prohibits bulk/offline prefetch.
No geometry, name, photo or token goes into a public tile URL: only z/x/y and
NASA's requested date. Tiles necessarily reveal the viewed geographic area.

NASA GIBS MODIS Terra true color uses GoogleMapsCompatible_Level9 (coarse imagery,
overzoom is display only). Static Reference_Labels_15m is **OSM reference labels**
with GoogleMapsCompatible_Level13, verified from live WMTS capabilities. Level9
returns HTTP 400 for that layer. Correct Level13 requests returned HTTP 500
repeatedly at field-scale zooms, although one low-zoom PNG succeeded. Consequently
hybrid is withheld in the final UI; no reliable hybrid coverage is claimed. A requested tile date does not prove
clear-sky coverage or a field acquisition at that time. These are visual maps.

References: https://operations.osmfoundation.org/policies/tiles/ ;
https://nasa-gibs.github.io/gibs-api-docs/ ;
https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/1.0.0/WMTSCapabilities.xml .

## NASA vegetation: discovery accepted, raster blocked

Current CMR UMM granules return CollectionReference.EntryTitle rather than always
ShortName/Version. The reader now accepts that shape only with the exact paired
collection concept ID and title, independently retrieved from CMR collections:
HLSS30 `C2021957295-LPCLOUD`, HLSL30 `C2021957657-LPCLOUD`, both v2.0. Unknown
concepts are rejected even when the query named HLS. Original UMM metadata stay
intact; exact acquisition, geometry, response hash and retrieval time persist.

Real discovery found acquisitions for the public regional test point in July
2024. A bounded attempted red-band range request redirected to Earthdata and
returned **401**. This environment has no Earthdata credentials. ORNL MOD13Q1
band/date discovery returned **503**. Receipts retain source URLs and statuses;
ephemeral signed redirect query strings are not retained. No NDVI pixels are
accepted. The existing aligned HLS red/NIR/Fmask numerical reader and conservative
QA tests remain unchanged. There is no completed NDVI map/selector/history here.

References: https://hls.gsfc.nasa.gov/data-products/ ;
https://cmr.earthdata.nasa.gov/search/site/docs/search/api.html ;
https://modis.ornl.gov/data/modis_webservice.html .
NASA collection citation/terms remain necessary when authorized pixels are added.

## ISRIC SoilGrids pH

Source: https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt .
The accepted VRT SHA256 is
`28bf9ceef0ee29a2d29926929b1760eddb6749b4f31ed212e8d536a226892f0d`.
Code_version v2.0.0, Outputs_version RUN05 and its March 2020 snapshot description
are model metadata, not on-farm observation dates. The mutable `latest` alias is
not treated as a new accepted release: changed manifest bytes fail closed until
separately reviewed. Source tile bytes and original retrieval times are also hashed.

The manifest is parsed, never executed by GDAL as a VRT. It selects exactly one
600×600 Int16 source TIFF at the confirmed point. Only a fixed HTTPS base and
strict tile-name pattern are permitted by transport; redirects are rejected.
The source TIFF is bounded by the existing 4 MB transport cap. Raster QA requires
explicit `-32768` nodata, one Int16 band, 600×600 shape, matching manifest affine,
250 m grid and interrupted Goode Homolosine projection with WGS84 ellipsoid.
The TIFF calls its datum unknown; the explicit projection/ellipsoid are checked
and the complete WKT retained. No surveyed datum accuracy is claimed.

At most 25 native cells are read around the point from that one tile. Cell
footprints are transformed to EPSG:4326 for display; nodata is transparent/null.
Raw pH×10 is divided by 10. Values outside 0..14 pH are rejected. Native coordinates,
row/column, raw values, scale/offset, depth, statistic, source hashes and missing
cells remain inspectable. No neighboring tile is silently substituted at edges.
Quantiles/uncertainty are unknown; the map is a modeled mean property, not a crop
suitability layer or laboratory sample. Existing WCS `read_ph_raster` and its
missing-nodata rejection were not changed or bypassed.

License/citation: ISRIC SoilGrids, **CC BY 4.0**;
https://docs.isric.org/globaldata/soilgrids/ ;
https://www.isric.org/explore/soilgrids/faq-soilgrids ;
https://doi.org/10.5194/soil-7-217-2021 .

## NOAA GFS temperature and limited conditions

Official NOMADS CGI: https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl .
Request only operational GFS 0.25° TMP at 2 m, a ≤0.5° bounded box and four leads
(0,6,12,24 h) from one conservatively delayed run. Each accepted GRIB must be one
band, ≤16 cells, geographic 0.25° spacing, NCEP operational TMP/2-HTGL with native
Kelvin units. Exact embedded reference/valid/lead times must match the requested
run; the point must lie within the returned grid. GDAL unit normalization is
explicitly disabled, then `C = K − 273.15`. Native Kelvin, normalized Celsius,
GRIB tags, source hash/URL, retrieval time and original grid remain present.

GRIB reference/model initialization time is verified. **Publication/issuance time
is unknown**, so `issued_at=null` and the UI calls this a partial forecast pathway.
No retrieval timestamp is substituted for issuance. f000 is model analysis, not
an observed current reading; sparse valid times are not daily extrema. Times are
UTC. Regional grid estimates are not exact field observations. Existing Open-Meteo
freshness/issuance gates and NASA POWER historical evidence are unchanged.

The only derived condition checks whether any sampled future temperature is
≤0 °C. This physical reference is explicitly not a crop damage threshold, frost
warning or diagnosis. A false result covers only sampled valid times. Missing
samples withhold the indicator; official warnings are null. No rainfall, flood,
storm, dry-spell or pest warning coverage is claimed.

NOAA US government data; retain NOAA/NCEP/GFS attribution. References:
https://nomads.ncep.noaa.gov/ ; https://www.emc.ncep.noaa.gov/emc/pages/numerical_forecast_systems/gfs.php ;
https://gdal.org/en/stable/drivers/raster/grib.html .

## Reports and refresh

Farmer reports retain their reported date, crop/name, optional planting date,
unknown growth stage/water/drainage, notes and `independently_verified=false`.
No new rule eligibility is granted. Calendar dates cannot be future reports;
planting cannot follow the observation. Photos remain in their existing private
stores with their existing authorization; no automatic photo migration occurs.
All source refresh is explicit. There is no scheduler or continuous monitoring.
