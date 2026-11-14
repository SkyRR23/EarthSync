# Quality report

Audit date: 14 November 2026. Findings below concern the contributed archive,
not the independently verified NASA backend. No original files were corrected,
and no contributed collection code was run. Checks establish byte integrity,
calendar coverage, numeric conversions and metadata gaps; they do not establish
ground truth, farm representativeness or agronomic validity.

## Decision

The pack is preserved and suitable for source review and offline adapter tests.
Soil conversions and valid MODIS numeric scaling can be reproduced. All new
numeric production integrations remain gated by the metadata and QA below.
Forecast CSVs are retained as unverified historical snapshots, not current
weather. Crop references, inferred drainage and current anomaly claims are blocked.

## Known concerns and evidence

### 1. Incomplete fetch log — confirmed

The 522 log rows contain no NASA POWER, forecast/current/archive weather or
flood requests, although their CSVs are present. `README.md` claims every number
is traceable to a log URL; this is not true for those families. Collector source
contains logging calls, so missing records cannot be explained as a deliberate
complete log format. Earlier runs or omitted logs are plausible, unproven causes.

Soil successes record `bytes=0` by construction. MODIS successes often target
synthetic filenames such as `modis_LST_Day_1km_MOD11A2.csv`; naive matching to
`modis_lst_day_hlegu.csv` misses them. The research fixtures match candidate
records by URL coordinates, product and band instead. No response body hashes,
original provider bodies or output hashes were contributed, so even matching
timestamps do not uniquely bind a final CSV to an HTTP response. Exact retrieval
times remain null in fixtures; candidate log row numbers preserve the available trail.

### 2. Expiring current/forecast data — confirmed metadata defect

Current CSV timestamps are `2026-11-14T11:30` without UTC offset. The column
`observed_at_local` is an author label: [Open-Meteo documents model-based current
conditions](https://open-meteo.com/en/docs), not a station observation.
Forecasts have 16 local dates, November 14–29, with no original daily units,
timezone response, retrieval timestamp, issue/run identifier or resolved model.
There is no evidence to compute an expiry deadline. A filename or ZIP timestamp
must not substitute for retrieval time. These files are not served as live data.
The entire forecast horizon is not declared expired merely because it was
downloaded earlier; live usability is unverified and fails closed.

Each forecast has exactly two missing values in each of `sm_0_7_m3m3`,
`sm_7_28_m3m3` and `soil_temp_0_7_c` (November 28–29): six missing cells per
location, 18 overall. Other forecast cells are present; zeros remain valid zeros.
Current precipitation's interval is absent and cannot be treated as a daily sum.

### 3. NDVI/EVI historical coverage and quality — confirmed

Each index has 46 unique, ordered composite start dates over 2024–2025:
January 1, then 16-day steps resetting each January; final start December 19,
2025. All expected starts and all numeric values are present. Scaling matches
raw × 0.0001 and documented integer range -2000..10000. This is record coverage,
not proof of usable surface observations.

No VI Quality / DetailedQA, pixel reliability, cloud/shadow/aerosol flags,
actual pixel geometry or definitive subset collection version are retained.
The CMR file names collection 061 for one granule, but cannot establish the
version of all ORNL subsets. Each numeric fixture is `observed` with method
“satellite-derived retrieval/index”, QA unknown and `usable_for_analysis=false`.

`api.txt` proposes anomalies against a 2024–2025 average and an example 18%
below-normal message. There is no 2026 numeric series, QA-screened comparable
current sample, validated seasonal baseline or uncertainty assessment. Neither
that message nor a disease/stress diagnosis is supported. No new baseline or
threshold has been invented.

### 4. LST fill values and missing composites — confirmed

Each day/night series has all 92 expected composite start dates across
2024–2025 (8-day steps reset annually, final start December 27). **There are no
missing composite-date rows in this final archive**, despite failed earlier
chunk requests in the log. Many rows have missing temperature values:

| Location | Day missing / 92 | Night missing / 92 |
| --- | --- | --- |
| Hlegu | 41 | 40 |
| Bago | 39 | 39 |
| Magway | 15 | 32 |

There are 206 missing values out of 552 positions. Every retained nonblank raw
code passes the documented range and raw × 0.02 − 273.15 matches contributed
Celsius to rounding. Empty raw/value cells remain null. The collector replaced
fill codes with blanks before export, losing which code/cause produced each gap.
No claim that every blank represents cloud contamination is justified.

The collector treats both 0 and 65535 as LST fill. The
[NASA MOD11A2 file specification](https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/MOD11A2)
lists 7500..65535 as valid range, night fill 0, and a day-fill table entry `NA`
while its QC note refers to day fill 0. Therefore **65535 is not a universal fill
rule**. Inspect actual version/band payload metadata and QA before applying
sentinels. No 65535 remains in the contributed CSVs, so any discarded instances
cannot be recovered. QC byte 0 can mean good quality, not a missing sample.

No QC_Day/QC_Night, clear-sky masks, observation counts or view information are
provided. MOD11A2's composite is an average of available daily LST retrievals;
having a composite does not prove eight valid daily samples. Land-surface skin
temperature is not air temperature at 2 m, and is not always crop canopy temperature.

### 5. SoilGrids units, depth, spatial support and uncertainty — partially validated

All 96 contributed rows (eight properties × four depths × three locations)
match the provider units and conversion factors in SOURCE_MANIFEST. All numeric
conversions match original `value_si` to its published precision. Example Hlegu
0–5 cm: pH code 63 → 6.3; clay 334 g/kg → 33.4%; nitrogen 274 cg/kg →
2.74 g/kg; bulk density 126 cg/cm³ → 1.26 g/cm³. CEC remains mmol(c)/kg.
The collector's unused SOILGRIDS texture constant says `g/100g`; the actual
CSV rows correctly say `g/kg`, which is what was validated. Blindly trusting the
constant or blanket `value_si` wording would be unsafe.

The WMS request selects `*_mean`, EPSG:4326, a 0.5° bounding box and pixel
50,50 in a 101×101 rendered map. ISRIC describes nominal native 250 m modeled
properties; that is not a surveyed farm footprint or the display-pixel size.
Actual native cell geometry/resampling and release need recovery before reuse.
Depths 60–100 and 100–200 cm and Q05/Q50/Q95 are absent. Measurement time is
not the retrieval date. Unknown uncertainty is explicit, not zero or a confidence
percentage. Texture sums 99.9–100.1% are preserved, not forced to 100%.

### 6. Drainage inference — blocked

`api.txt` proposes deriving drainage from clay and bulk density, and separately
mentions a clay/Ksat proxy. Twelve Ksat requests failed with “no value in WMS
answer”; no Ksat or drainage measurements exist in the soil CSVs. Neither proxy
has a supplied method, calibrated thresholds, applicability study or validation
for Myanmar. Bulk density is not hydraulic conductivity. Fixture drainage is
`unavailable`; it must not populate the engine's farmer-reported drainage enum.

### 7. CMR boundary — confirmed

Collector bbox `95.8,16.7,96.6,17.5` uses
[CMR west,south,east,north order](https://cmr.earthdata.nasa.gov/search/site/docs/search/api.html).
Hlegu and Bago are inside; Magway (94.93 E, 20.15 N) is outside both the west
and north bounds. The comment “covers all three” is false. The output reports
only the latest matching 2025 granule, with `page_size=1`, not temporal or per-point
coverage. Empty ECOSTRESS/GEDI results establish only that this particular query
returned nothing; neither Myanmar-wide nor Magway absence follows.

A future review should query each exact point/field geometry, collection version
and requested interval, paginate where needed, and check actual granule footprint
and valid-pixel coverage. A regional box containing all three still would not
prove coverage at each point. No replacement search was run during this audit.

### 8–9. Missing crop catalog and integration artifacts — confirmed

The archive has no crop-reference catalog, `crop-profiles.v1.json`,
`field-context.<loc>.v1.json` or `scripts/build_data.py`. Its README refers to
these as existing integration dependencies. Their contents and claimed rules
cannot be reconstructed from sample text. Existing repository synthetic crop
fixtures are not substitutes for validated Myanmar references. No crops, crop
requirements, farmer reports or field-context values are invented here.

### 10. Compatibility with verified backend — protected

Reviewed read-only at backend commit
`4befe7d1e204c875436ab486c231edcbb944f317`:
`server/earthsync/power.py`, `server/earthsync/models.py`,
`server/docs/NASA_POWER.md`, and its recorded source review.
The current branch is newer than the backend worktree's earlier local branch;
the review used the fetched remote commit, not that stale checkout.

The backend requires original `T2M=C`, `PRECTOTCORR=mm/day`, finite declared
fill, `time_standard=LST`, `sources=["MERRA2"]`, and exact request/header
interval. [POWER methodology](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/)
also describes GEOS-IT continuation: recent values cannot all be called MERRA-2.
The pack's stripped CSVs cannot pass these metadata checks. Additional radiation
columns have separate lineage and must not inherit a blanket MERRA-2 label.

For each variable, all Gregorian calendar days must have valid finite values:
any missing/invalid day nulls that whole month's aggregate. Daily precipitation
rate × one day is summed in mm; daily mean T2M is averaged. No scaling partial
months, gap filling, monthly-rate substitution or forecast fallback is allowed.
The pack's daily series starts mid-July and ends mid-November; November 11–12
T2M and precipitation are blank at all three points. Complete-looking August–
October CSV rows alone cannot establish accepted lineage or source validity.

LST in the POWER contract means **Local Solar Time**, a 15° swath convention;
it is not Myanmar civil time or MODIS **land-surface temperature**. Unit/source
checks cannot be replaced by matching filenames or averaging MODIS temperatures.
The optional adapters remain outside this pipeline and outside current Rust input
types. No production code or stable contract has been changed.

## Additional confirmed defects and limitations

- **Climatology month shift:** every parameter in every location has numeric
  months 1..12 paired with `FEB..DEC,ANN`. January is missing; the annual value
  occupies the month-12 slot. `fetch_power_climatology` slices columns `[2:14]`
  as though a year column existed, consistent with this loss. The absent original
  header prevents a full reconstruction; retain raw and block all climate-normal
  use. The claimed 2001–2025 baseline is not established by any retained header.
- **Daily coverage claims:** the “120-day” POWER files contain 121 dates because
  the requested endpoints are inclusive. The “365-day” archive files contain
  364 dates due to excluding the last two days. Describe actual coverage.
- **Archive lineage:** `fetch_openmeteo_archive` selects no explicit model.
  ERA5-Land and IFS comments/filenames cannot authenticate the returned mix.
- **Terrain:** `north_km_offset` / `east_km_offset` store grid indices at 0.02°
  spacing, not kilometres. `slope_to_center_pct` is a central-difference regional
  estimate using fixed 2.22/2.13 km distances, not a field slope observation.
  A 5×5 sample over kilometres does not retain a 90 m DEM raster.
- **Map imagery:** Hlegu/Bago JPEG hashes match within every layer because the
  requests use the same tile coordinates. This is expected shared map coverage,
  not independent plot measurements. VIIRS NDVI browse imagery is not MOD13Q1
  numeric NDVI. Different layer dates/resolutions cannot be combined as one sample.
- **Land cover and US examples:** annual IGBP land-cover classes cannot identify
  farmer crops or histories. Nevada SSURGO drainage categories and 3DEP values
  have no Myanmar applicability.

## Collection-script review and failure accounting

Reviewed the complete preserved collector statically. It uses the Python
standard library, TLS default validation, public provider URLs, local CSV/JPEG
writes and a USDA read-query POST. No subprocess/eval/exec, shell installation,
credential values or collection-time code downloads were found. API-note keys
are placeholders, not supplied secrets. This is a source inspection, not approval
of every external response or a reason to run the collector in raw/.

Operational issues: relative-to-script writes overwrite with `--force`;
skip-existing files can mix capture ages; TODAY changes coverage; default models
and WMS layers are mutable; retries are collapsed in the log; response reads are
unbounded; error status is replaced by `-`; the generic numeric helper does not
reject NaN/infinity/booleans and hardcodes POWER fill handling; dates deduplicate
silently in MODIS output; one chunk's scale is applied to merged chunks; provider
headers, geometry, QA and units are discarded. None of these behaviors is adopted
by a production integration. The collector remains preserved unchanged.

Of 81 failed records: 42 MODIS requests exceeded ORNL's ten-date subset limit,
27 GIBS tile requests failed (notes include HTTP 400), and 12 soil Ksat parses
failed. Later successful narrower MODIS chunks and supported GIBS levels coexist
with these failures; failed attempts are retained, not relabeled as successful.
The final LST row calendar is complete while its measurements remain incomplete.
Unlogged API availability claims in `api.txt` are unverified, including claimed
unauthenticated failures for other APIs.

## Reproducible checks and limits

Run the README commands. Tests check archive traversal/link/collision/size/CRC
handling, byte-identical preservation, deterministic regeneration, source links,
soil arithmetic, calendar counts, LST nulls, forecast gaps, missing metadata,
and the confirmed log/climatology defects. They run offline and never import
the contributed collector. They do not certify scientific accuracy, QA flags,
weather freshness, farm representativeness, crop rules, API uptime, or backend
end-to-end integration. The independent live backend's recorded verification
is not claimed as a new live test performed by this audit.

Recorded validation result: 17 offline tests passed; staged `git diff --check`
passed. Raw files use scoped `-text -whitespace` Git attributes to preserve their
original CRLF and formatting; archive/member hashes independently check their bytes.
