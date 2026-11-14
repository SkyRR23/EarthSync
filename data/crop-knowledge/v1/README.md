# EarthSync crop knowledge: initial global pilot evidence

This pack provides an offline, machine-readable regional reference catalog and
working source-capture, lookup, validation and audit commands. It contains seven
crop profiles and one separate fallow profile across four pilot systems, backed
by 13 original institutional sources. **It cannot authorize crop recommendations.**
The crop schema is a [proposal for the 7E owner](CONTRACT.md), not an engine input
or a replacement for Flutter, Python, NASA POWER, Rust integration or v0.2 APIs.

| Pilot | Initial profiles | Reviewed coverage |
| --- | --- | --- |
| Story County, Iowa | Rainfed corn; rainfed soybean | Detailed parameter/source desk review. Partial statewide planting/establishment guidance, taxonomy and qualitative seedbed conditions. |
| Tribune / Greeley County, Kansas | Dryland winter wheat; grain sorghum; fallow | Reference-only research-station rotation context. No recommended farm sequence or numerical requirements. |
| Stuttgart, Arkansas | Flooded irrigated rice; irrigated soybean | Reference-only water/drainage management. Soybean irrigation chapter is historical (2000). |
| Griffith / Riverina, Australia | Drill-sown irrigated rice with delayed permanent water | Reference-only NSW summary; full guide/cultivar calendar unverified. Other regional crops remain gaps. |

These regions define initial evidence coverage, not EarthSync's geographic
availability. Lookup outside them returns unavailable evidence, not an unsuitable
location. A pilot label is not a farm boundary. None of the four case datasets
includes a user's approximate location, farmer-confirmed farm, photo, current
forecast, soil sample or other environmental observation.

## Reproduce and use

From the repository root, Python 3.12 or newer:

```sh
python -m venv /tmp/earthsync-crop-knowledge-venv
/tmp/earthsync-crop-knowledge-venv/bin/python -m pip install -r data/crop-knowledge/v1/requirements.txt
/tmp/earthsync-crop-knowledge-venv/bin/python data/crop-knowledge/v1/tools/catalog.py check
/tmp/earthsync-crop-knowledge-venv/bin/python -m unittest discover -s data/crop-knowledge/v1/tests -v
/tmp/earthsync-crop-knowledge-venv/bin/python data/crop-knowledge/v1/tools/catalog.py lookup --pilot us_ia_story --crop corn --system rainfed_upland
```

The same commands work with an existing Python environment that has the pinned
`jsonschema` dependency. Windows can use a local venv and its
`Scripts/python.exe`; these Windows commands were not tested in this task.

Lookup requires exact crop, pilot and production-system IDs. It has no geographic
guessing, aliases, score, nearest-region fallback, generated scenarios or hidden
conversion to an engine enum. A successful lookup retains unavailable properties
and `recommendation_eligible: false`; it is not an assessment of a farm.

The four editorial inputs are:

- `sources.json`: original institutional URLs, attribution, versions and precise
  or explicitly unknown publication dates.
- `evidence/claims.json`: individual claim locators, limitations, evidence kind,
  date/spatial support, applicable pilot/system scopes and parameter keys.
- `profiles.json`: stable crop/system/profile IDs, typed parameter envelopes,
  explicit unknowns and review/coverage limits.
- `pilots.json`: named regional scopes, coverage and inventory of profiles.

`evidence/captures.json` holds selected attributed excerpts and the UTC time of
the successful web extraction batch. It is separate from those editorial inputs.
To regenerate the bundle, pilot reference cases and checksum audit after review:

```sh
python data/crop-knowledge/v1/tools/catalog.py build
python data/crop-knowledge/v1/tools/catalog.py check
git diff --check
```

`check` rebuilds in memory and rejects data, generated-case or checksum drift.
It never rewrites artifacts. `build` does not visit sources or verify new facts;
changing data requires a source review, followed by review of the resulting diff.
Hashes establish stored artifact integrity, not agricultural truth or independent
approval. The generated audit records every file's hash scope and byte count.

## Source retrieval and licensing

The successful source review on 14 November 2026 used the web research tool.
Direct HTTP source capture in this execution environment was separately attempted
for all 13 sources and **failed with proxy tunnel 403**. Exact failure receipts
are in `evidence/http-retrieval-audit.json`. Original provider bytes, response
headers, original retrieval times and original-response SHA-256 are unavailable.
No web extraction has been presented as an original provider HTTP response.

`evidence/captures.json` contains short selected excerpts, not complete snapshots;
`audit.json` hashes the stored extracts and data artifacts. The tool batch
completion timestamp is explicitly distinguished from the unknown upstream
provider retrieval time. Publication dates come from source bodies/indexes, not
search-result ages. Copyrighted articles, images and PDFs are not redistributed.
Full-response redistribution rights were not established in this pack.

The reproducible fetcher is usable where direct source access is available:

```sh
python data/crop-knowledge/v1/tools/capture_sources.py --output /tmp/earthsync-crop-sources-new-run
# Or limit a new run to one registered source:
python data/crop-knowledge/v1/tools/capture_sources.py --source isu_soil_2026 --output /tmp/earthsync-crop-source-new-subset
```

The output directory must be new. The fetcher uses bounded timeouts/downloads,
preserves exact successful response bytes and their hashes, and records every
failure as unavailable with null values. It exits nonzero if any selected source
is unavailable. Downloaded files remain local pending license and content review;
they are never executed, automatically imported into the catalog or promoted to
reviewed facts. A login/challenge HTML page can only be downloaded for manual
review, never accepted as agricultural evidence. PDF signatures are checked.

When licensing and access permit future original-response snapshots, preserve
them byte-for-byte with the provider URL, timestamp, hash, version, attribution
and exact redistribution basis in a reviewed addition. Do not replace this
historical web-excerpt audit with a later response and call it the original.

## Evidence semantics and limits

`available` means a source-backed reference is supplied. `reviewed` means a
parameter/source **desk review** within the stated limits; no independent
agronomist sign-off or field experiment was performed here. `reference_only`
facts cannot be promoted by virtue of being cited. Synthetic data is reserved
for explicitly labeled software tests. Missing values are null with a reason,
not zero, a favorable condition or an unconstrained rule. Fallow taxonomy is
explicitly not applicable rather than missing crop evidence.

Knowledge references distinguish published guidance, reported research,
taxonomy and a method reference. None is relabeled as observed, modeled,
forecast or farmer-reported environmental data. `spatial_support.field_specific`
is false for every claim. Regional guidance has no invented raster resolution.
An unknown publication date or measurement depth remains unknown.

Iowa's advisory calendar endpoints are not insurance dates or hard biological
limits. The soybean start date stays unknown. The 2026 establishment advice
concerns **soil** temperature with warming/seedbed conditions, not NASA POWER
monthly air temperature. No current forecast was retrieved. A historical
two-inch temperature reference is not a soil sampling layer or root-depth rule.

FAO-56 equation 56 is retained as a method claim. No Kc, stage duration, ET0,
water balance, crop water budget or flooded-rice irrigation quantity is invented.
The source method is not a regional crop coefficient. All harvest windows,
durations, air-temperature limits, soil-depth requirements and crop coefficients
remain unavailable in this initial catalog. Family identities do not imply
succession restrictions, disease reduction or legume benefits.

See [the review and gap register](EVIDENCE_REVIEW.md) for parameter-by-parameter
Iowa review and the remaining authoritative-data work. The collected research
pack from [PR #11](https://github.com/SkyRR23/EarthSync/pull/11) is not copied or
cleared by this change. Its missing provenance, shifted months and absent QA
motivate rejection tests; it supplies no crop thresholds here.

## Verification record

The local validation commands and final outcomes are recorded in
`VALIDATION.md`. The dedicated workflow runs only offline checks and has no
production integration step. No browser, Android, live crop API, farm ground
truth, yield, forecast accuracy or scientific field validation is claimed.
