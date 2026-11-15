# Provider availability and provenance

Subject `660b479c3ffb714cd1d489e1241c026ceae6ed67`. [Main receipts](evidence/provider-receipts.json) record **188 fresh successful production HTTP requests and 12 disk-cache hits** during the frozen run. Repeated cached bodies are not new observations. Supplemental probes are separate: 24 TLS-verified display tiles, four hourly POWER UTC/LST audit bodies, NOAA station/catalog/reference retrieval and one HLS metadata discovery. GFS consistency was rechecked from cached real records; final summary reports zero supplemental forecast network attempts on that recheck. Do not add these cached results as new provider acquisitions.

| Provider | Measured availability | Scientific limit |
|---|---|---|
| NASA POWER | 24/24 periods, seven production parameters, exact LST/date/source hashes | Regional MERRA-2 and radiation supports differ; not exact farm measurements |
| ISRIC SoilGrids WebDAV | 12/12 bounded mean pH raster extractions | 0–5 cm, 250 m modeled grid; uncertainty and independent held-out samples unavailable |
| NOAA GFS | Four native temperature records at two sites | 0.25° regional model; initialization is not issuance time; later observations not matched |
| NASA GIBS true color / OSM | 24/24 dated/display tile requests | Not quantitative greenness or crop health; not 12 browser map render demonstrations |
| NASA HLS CMR | One actual metadata record discovered | Accepted authorized QA pixels/NDVI unavailable; no true-color substitution |
| NOAA Global Hourly | Two valid annual station CSVs via official public AWS archive | Station temperature only; assimilation independence unknown |
| Official issued hazard alerts | UNAVAILABLE | No fictional official warnings |

NOAA original annual NCEI URLs returned HTTP 200 with HTML rather than station CSV; the parser now rejects these in this **test harness**. The official NOAA Open Data archive fallback supplied actual station data: [NOAA ISD archive](https://registry.opendata.aws/noaa-isd/), [NOAA service location change](https://www.nesdis.noaa.gov/news/service-location-change-integrated-surface-data-global-hourly). Source/content hashes and station metadata are in [reference availability](evidence/reference-availability.json). TMP codes 1 and 5 only; missing 9999 rejected. [ISD format documentation](https://www.itl.nist.gov/div898/winds/NIST_TN/doc/ish-format-document.pdf) and [POWER time documentation](https://power.larc.nasa.gov/docs/services/api/temporal/hourly/) explain QC/time handling.

[SoilGrids documentation](https://docs.isric.org/globaldata/soilgrids/) and [method paper](https://doi.org/10.5194/soil-7-217-2021) describe model/training support. SoilGrids CC BY 4.0 attribution is retained; the application's NASA/NOAA/OSM and original source attributions remain unchanged. Public study-coordinate citations are in the frozen manifest; downloaded papers, annual CSVs and rasters are not redistributed in Git. Reproduction users must check source terms and access permissions.
