# Source trace and review — 14 November 2026

Read before implementation: [PR #11](https://github.com/SkyRR23/EarthSync/pull/11)
at immutable head `a85e2dd48805a36faebfec93c6991d5babb1add2`:

- `data/research/field-shift/README.md`
- `data/research/field-shift/SOURCE_MANIFEST.md`
- `data/research/field-shift/QUALITY_REPORT.md`
- `data/research/field-shift/INTEGRATION_PLAN.md`

Read using `git show origin/pr-11:<path>` after fetching
`pull/11/head:refs/remotes/origin/pr-11`. No PR #11 files or numbers were copied
into production inputs. Its source audit supplied limitations and conversion
cross-checks, not independently authenticated provider response bodies.

Provider documentation was independently read through the web reader on the
review date. The shell could not capture these documents because the environment
blocks those hosts; these links and review notes are not original data-retrieval
evidence or hashed metadata captures.

| Primary source | Verified semantics / implementation decision |
| --- | --- |
| [ISRIC layers](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html) | Mapped integer units and divisors below; six standard depths, distinct mean/quantiles; nominal 250 m modeled maps |
| [ISRIC access](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_02.html) | REST temporarily paused, without restoration estimate; WCS recommended for modeling subsets; WMS for visualization/overview; five REST requests/minute fair use; CC BY 4.0 |
| [SoilGrids REST docs](https://rest.isric.org/soilgrids/v2.0/docs) | Swagger entry identified; no readable live schema/body was obtained here. REST provider-shaped fixtures are synthetic tests, not verified live schema captures |
| [Open-Meteo forecast](https://open-meteo.com/en/docs) | Units, daily/current response blocks, explicit model/timezone selection, nearest grid, disabling downscaling; current is modeled; current interval describes backward-looking aggregations; generation time is processing duration |
| [GFS metadata](https://open-meteo.com/en/docs/gfs-api) | Explicit global GFS selector, nominal ~13 km surface model and six-hour update cadence; no per-response initialization identity is inferred |
| [Open-Meteo terms](https://open-meteo.com/en/terms) | Attribution/data-license and free-service access distinction carried from audited manifest; commercial eligibility still requires review before production |
| [MOD13Q1 specification](https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/MOD13Q1), [MOD11A2 specification](https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/MOD11A2) | Source references from PR #11's audit; no new original MODIS/QA response was obtained. Numeric adapters remain unavailable |

Conversions implemented from mapped units, without cross-depth averaging or
texture renormalization:

| Property | Mapped units | Divide by | Output |
| --- | --- | ---: | --- |
| pH water | pH × 10 | 10 | pH |
| clay, sand, silt | g/kg | 10 | % by mass |
| organic carbon | dg/kg | 10 | g/kg |
| total nitrogen | cg/kg | 100 | g/kg |
| CEC at pH 7 | mmol(c)/kg | 10 | cmol(c)/kg |
| bulk density | cg/cm³ | 100 | kg/dm³ |

Soil REST data shape/unit spelling remains a conservative integration hypothesis
until a fresh original body can be replayed. Exact mapped-unit/divisor changes
are rejected. Output-unit conversions are computed from mapped units; a
provider's suggested target-unit label is not blindly applied. Release remains
null because API v2.0 and endpoint ETags do not establish a dataset release.
Do not infer observation date from retrieval time. Model quantiles remain named
quantiles, not confidence or measurement error estimates.

Weather uses ISO dates with the provider-returned **fixed** UTC offset for the
entire response, including across DST. The requested IANA timezone and original
offset are preserved. No DST-aware local-day reinterpretation is performed.
Current temperature/humidity are instantaneous values; no current precipitation
interval is invented. Daily precipitation is an accumulation in mm. A named
selector is not a verified run identifier. The optional model-run freshness
policy is tested with fixed synthetic clocks; the generic response always lacks
the required issue identity and therefore cannot pass the live-use gate.

## Actual verification record

[provider_probe_blocked.json](provider_probe_blocked.json) is the output of the
explicit Python probe in this worktree. Soil and weather both returned
`UPSTREAM_TRANSPORT_UNAVAILABLE`, with UTC request times and no HTTP response,
retrieval timestamp, response hash or scientific values. Earlier standard-library
probes to `docs.isric.org`, `maps.isric.org`, `rest.isric.org`, `open-meteo.com`
and `api.open-meteo.com` reported CONNECT 403. The environment status tool
confirmed a restricted, enforced allowlist without these destinations. These
are environment connectivity failures, not independent evidence of upstream
provider downtime. The documented SoilGrids pause is separate evidence.

Needed for later source acceptance: narrow network grants for the intended
provider and documentation hosts, a restored or alternative verified soil
service, immutable fresh response/metadata captures, source release and native
spatial support, and independently reviewed weather run timing. No access
policy was bypassed or changed. Historical POWER was not queried as a fallback.
