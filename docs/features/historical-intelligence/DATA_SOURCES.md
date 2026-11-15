# Sources, provenance and rights

| Source | Original identity / support | Use and limits |
|---|---|---|
| NASA POWER daily API v2.10.3 | MERRA2 meteorology; 0.5° × 0.625° regional context | PRECTOTCORR, T2M, T2M_MIN/MAX, T2MDEW, WS2M, PS; original parameter, native unit, source header and LST dates retained |
| NASA POWER SYN1DEG | ALLSKY_SFC_SW_DWN; 1° radiation | Inputs to existing Rust ET0; no product substitution |
| EarthSync Rust FAO-56 | `fao56-daily-pm.v1`; executable SHA-256 | Derived reference-grass ET0; parent IDs/hashes and missing reasons retained |
| NASA GIBS | `MODIS_Terra_CorrectedReflectance_TrueColor`, EPSG:3857 Level9 | Capability-checked requested daily tiles; acquisition date unknown, no NDVI |
| ISRIC SoilGrids | accepted RUN05 WebDAV pH, 0–5 cm, native 250 m | Existing static modeled-cell extraction and version pins; CC BY 4.0 attribution |
| 7P / 7V reference catalog | unchanged profile/source/review IDs and scope | Reference identity/traits only; no executable suitability rules |
| Farmer journal | existing local records with reported/recorded dates | Farmer reports and plans remain unverified and distinct from simulated inputs |

Documentation:

* NASA POWER daily API: <https://power.larc.nasa.gov/docs/services/api/temporal/daily/>
* GIBS time and tile access: <https://nasa-gibs.github.io/gibs-api-docs/access-basics/>
* FAO-56: <https://www.fao.org/4/X0490E/x0490e08.htm>
* SoilGrids: <https://www.isric.org/explore/soilgrids>
* OpenStreetMap: <https://www.openstreetmap.org/copyright>

NASA attribution and original source messages remain in Evidence. No new source
license grant is asserted. Existing repository/catalog licenses and 7V review
restrictions continue. SoilGrids requires ISRIC/SoilGrids CC BY 4.0 attribution;
map streets retain © OpenStreetMap contributors. Provider links/headers, source
version, units, native spatial support, requested/actual periods, retrieval time,
response hashes and normalization are retained rather than replaced by screenshots.

Live software verification uses a Myanmar regional test point and synthetic
confirmed farm geometry/history, not a recruited farmer or agricultural ground
truth. Exact private raw captures stay outside Git. Tests cover full calendar
years 2015–2025 using the source versions above. A regional source-consistency
test does not establish station-level accuracy. PR #31's independent validation
was consulted for context, not merged or claimed as new verification here.
