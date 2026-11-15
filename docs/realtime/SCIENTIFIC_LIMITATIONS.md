# Scientific boundaries

All **60 crop-rule candidates remain blocked**, with **zero approved executable
crop-suitability recommendations**. The original Rust FAO-56 calculations,
scientific source packages and immutable input pins are unchanged.

| Evidence | Meaning and limits |
|---|---|
| Iowa station | Point sensor at the named station, with actual time/depth/units; nearby evidence is not an inside-field measurement |
| NWS | Official prediction or issued alert, with original validity and authority; not measured current weather |
| Open-Meteo / GFS | Model forecast; possible shared underlying models; no independent forecast-skill claim |
| IMERG Early V07 | Regional satellite-derived half-hour precipitation estimate; delayed, 0.1° support; not a gauge or instantaneous rain |
| SMAP L4 V008 | Approximately 9 km model-assimilated 0–5 cm / 0–100 cm soil moisture, normally multi-day delay |
| HLS-VI v2 | Native NDVI at one QA-accepted 30 m cell; clouds/fill/high aerosol rejected; not a health percentage or polygon mean |
| SoilGrids | Versioned modeled 0–5 cm reference pH, nominal 250 m support; not a live sensor or laboratory test |
| NASA POWER | Dated climate reference; not current station weather |
| Farmer reports/photos | Explicit reports and protected owned media, distinct from environmental observations |

Numeric acceptance checks encoding, grid/time/units, missingness and documented
quality metadata. It does not establish independent field accuracy. IMERG's
qualitative quality index is preserved without inventing an unsupported “high
quality” threshold. SMAP native atomic/J2000 time is retained; CMR's observation
interval is used without pretending the native counter is already UTC.

Latest accepted HLS at Ames can be weeks old. The UI shows its actual acquisition
date and delayed-source state. No-data/cloud pixels never become vegetation
decline. True color and metadata discovery never become numeric NDVI.

Monitoring is displayed alongside baseline/A/B. It does not automatically change
saved assessments, run crop rules, rank strategies, prescribe irrigation or
fertilizer, predict yield/profit, or guarantee rotation benefits. The deterministic
assistant continues to explain the saved evidence and original citations.
