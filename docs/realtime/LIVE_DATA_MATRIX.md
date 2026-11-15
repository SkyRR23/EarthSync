# Live data and geographic coverage

Machine-readable public-reference receipts are in `evidence/live-providers.json`
and `evidence/verification-summary.json`. Provider status is time-specific; later
outages or stale states must remain visible rather than reusing these receipts as
current observations.

| Source | Ames | Secondary locations | Scientific/access limits |
|---|---|---|---|
| Iowa ISUSM | Actual minute-table temperature, rain, humidity, wind, SoilVue moisture by depth | Crawfordsville verified; outside Iowa unavailable | Online metadata is not proof of every sensor; native missing/QC handling |
| NWS daily/hourly | Actual `/points` discovery and forecasts | Crawfordsville and Davis verified | US coverage only; no NWS warnings for Myanmar |
| NWS grid | Native precipitation amount intervals, humidity and wind | Covered US points | Totals retain full original interval, no invented hourly amounts |
| NWS alerts | Actual active-feed response, including verified empty state | Covered US points | Failed/stale feed is unverified, never all-clear |
| Open-Meteo | Actual success and separately recorded provider outage/recovery | Crawfordsville, Davis, Yangon, Mandalay actual requests | Model blend; no independent station/skill claim; free API terms apply |
| NOAA GFS | Original temperature path preserved; extended weather/accumulation samples read from actual GRIB | Global model coverage, bounded regional request | Sparse leads, not observed weather; ten-second request spacing |
| IMERG Early V07 | Authorized native precipitation + quality/time bounds | Global product coverage; current candidate initially verified at Ames | Several-hour delay and 0.1° regional estimate |
| SMAP L4 V008 | Authorized native surface/root-zone cell | Global product coverage; numeric verification initially Ames | Multi-day delay, ~9 km, assimilated model estimate |
| HLS-VI v2 | Real NDVI 0.539 after rejecting newer cloudy candidates | CMR discovery for secondary public points | 30 m point support; accepted acquisition can be weeks old |
| SoilGrids WebDAV | Existing modeled pH gate passed with actual source | Existing supported global reference path | 250 m, 0–5 cm; extra properties not yet accepted/integrated |
| GIBS / OSM | Existing mapping retained; direct tile access tested separately | Coverage/layer-dependent | True color is visualization, not NDVI; hybrid failures stay disclosed |
| NASA POWER / Rust | Preserved live/cached-real reference and actual Rust journey | Existing global reference contracts | Dated climate, not instantaneous weather |

HRRR remains optional: official inventory was inspected; no separate HRRR data
pipeline or forecast-skill claim is made. Additional SoilGrids properties are
deferred until their units, native support, nodata and version manifest have been
accepted; existing pH is not weakened to accept an unreviewed dataset.
