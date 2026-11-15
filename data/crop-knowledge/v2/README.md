# Global crop reference evidence v2 — EarthSync 7P

This is an **offline reference package**, not validated crop advice. It contains
the five priority crops, regional Myanmar calendar references, a conservative
global agricultural identity import, traceable claims, rotation research examples
and an identity-only Rust v0.3 exporter. No model training or second decision
engine is introduced.

All new crops/profiles have `recommendation_eligible: false`,
`approved_for_candidates: false`, `review: reference_only`. Executable rule lists
are empty. The schema and semantic validator reject promotion. Source desk review
does not establish independent agronomic acceptance or farm applicability.

## Run locally

From the repository root, with Python 3.12+:

```sh
python -m venv /tmp/earthsync-crop-v2
/tmp/earthsync-crop-v2/bin/pip install -r data/crop-knowledge/v2/requirements.txt
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py check
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py lookup rice
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py lookup 'mung bean'
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py lookup sesame
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py lookup groundnut
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py lookup maize
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py list --category legumes_pulses
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py trace rice.global.ecology@1 --parameter annual_precipitation
```

After dependency installation, these commands have no network requirement. Python
callers can use `load()`, `lookup()`, `project()` and `mapping_report()` from
`tools/knowledge.py`. Loading verifies exact stored hashes and the complete graph.
There is no server, database or GPU dependency. JSON/JSONL suit this data scale;
SQLite and Parquet would add unnecessary indexing/storage machinery here.

Lookup accepts exact stable IDs, scientific names or exact case-insensitive
aliases. Shared aliases return `ambiguous` with every matching ID. For example,
`corn` has conflicting species uses in the historical source; use `maize` or
`ecocrop.2175@1`. Region, system and cultivar filters never select a nearby or
generic fallback. Country/AEZ labels do not locate a user's farm.

## Contents and evidence boundaries

| Artifact | Meaning |
| --- | --- |
| `catalog.json` / `catalog.schema.json` | Versioned sources, claims, crop identities, profiles and ordered reference rotations; strict JSON Schema plus semantic checks |
| `originals/` / `original-manifest.json` | Exact permitted FAO/mirror bytes and small rejected SoilGrids diagnostic captures, with separately pinned original hashes |
| `species-inventory.jsonl` | All 2,568 distinct ECOCROP snapshot species, including excluded plants and their exclusion basis |
| `editorial.json` | Reviewed priority identities/aliases and explicit calendar crosswalk dispositions |
| `sources.json` / `dataset-versions.json` | Exact access URLs, publisher, version, publication precision, retrieval evidence, rights and limitations |
| `dataset-inventory.json` | All five mandatory datasets: access, schema, licensing, coverage, resolution, units, cadence and restrictions |
| `nasa-compatibility.json` | Existing numerical evidence versus imagery/discovery context, unintegrated products and access limits |
| `evidence/myanmar-calendar-facts.json` | Selected factual priority sessions, retaining original JSON locators, zone, season, remarks and update date |
| `evidence/calendar-disagreements.json` | Unresolved identity/name/duration discrepancies, never a favorable-source selection |
| `evidence/taxon-checks.json` | Five independently fetched GRIN species/family checks; selected facts, not original full-response snapshots |
| `evidence/retrieval-receipts.json` | Successful and failed attempts, exact response hashes, sizes, URLs, selected headers and truthful timestamp precision |
| `missing-parameters.json` | Every unavailable field per profile, with explicit null and reason |
| `mapping-report.json` | Parameter → proposed v0.3 condition → blocked reason, including source-claim links |
| `fixtures/` | Eight requested rotation examples plus overlap/reversed-order native Rust requests |
| `open-source-reuse.json` / `research-leads.json` | Inspected tools/licenses and further official/original agricultural research leads |

The catalog includes **708 agricultural identities**, selected by explicit
cultivation attributes and agricultural use categories, with separately checked
priority exceptions. Most additional species have identity records only. The
2,568-source inventory is not a claim that every plant is a crop. Wild-only,
ornamental-only, forest-only and ambiguous material/environmental records are
excluded unless separate positive agricultural evidence is recorded. Cultivated
forage plants have a documented forage category; arbitrary grass is not promoted.
Fiber/industrial/oilseed expansion needs specific agricultural-use evidence when
ECOCROP's generic `materials` category cannot establish it.

The OpenCLIM CSV is a **third-party historical snapshot**, not an official FAO
bulk export or a completely independently authenticated table. Its exact commit,
encoding and bytes are retained. The official FAO catalog identifies ECOCROP as
CC BY 4.0; no license for OpenCLIM code is assumed and none is copied. Only
priority descriptor fields independently checked against original FAO sheets
populate numerical/ecological profiles. No additional mirror growing requirements
are imported. See [rights and provenance](RIGHTS.md).

## Priority crop profiles

Rice (`ecocrop.1574@1`), mung bean (`ecocrop.2150@1`), sesame
(`ecocrop.1937@1`), groundnut (`ecocrop.2199@1`) and maize
(`ecocrop.2175@1`) each have a global ecological profile, a FAO-56 method/coefficient
reference, regional calendar context where present, and explicit missing fields.
There are 75 profiles in total, including two identity-only Tribune research
profiles. No profile is described as agronomically complete.

Global ECOCROP envelopes remain separate from regional profiles. The original
temperature query uses environmental **average minimum/maximum growing-season
temperatures**; these cannot bound every daily Tmin/Tmax. The annual rainfall
descriptor is recorded in **mm**, with annual temporal support and the provider's
supplemental-water caveat. It cannot be divided, prorated or substituted for
growing-period rain, actual crop water use or ETc. Altitude lower bounds and
missing soil categories remain null. Ecological soil-depth classes are not
sampling horizons. No chemical method/depth is invented for ecological pH.

Myanmar is actually present in the official Crop Calendar API: the captured list
has 58 countries, six Myanmar AEZs and 111 Myanmar records, all marked updated
2021-02-26. Fifty-five priority sessions are retained. Advisory periods, duration,
season names and remarks remain separate; their endpoints need not form a
consistent planting-to-harvest pair. `Summer Rice` sometimes starts in November;
it is not remapped into an invented national March–May rule.

Important unresolved source differences are retained:

- FAO code `0157` says Green gram / `Vigna aureus`; code `0232` says Mung bean
  globally but Penauk in Myanmar's identity endpoint, with different durations.
  Both are tentative research associations with mung bean; identity-disputed
  calendar profiles cannot be exported automatically.
- Code `0113` is Maize in the country endpoint and Corn, sweet elsewhere.
  Species identity alone does not resolve the harvested crop type or duration.
- Groundnut's handbook erect-type 90–100-day reference and distinct calendar
  durations remain in separate scopes. The handbook's prostrate duration in
  months is not converted to a fixed number of days. The type-group scope is not
  a selected named cultivar.

Rice references distinguish flooded irrigated lowland, rainfed lowland, an upland
calendar whose water supply is unspecified, an explicitly unverified rainfed
upland research target, and NSW drill-sown/delayed permanent water. Irrigated
calendar labels do not prove maintained flooding. No flooded management or paddy
Kc is applied to the upland profile. FAO-56 coefficients preserve endpoint
alternatives/footnotes and missing initial-row values; they have **no stage
offsets, locally accepted adjustments or daily ET0**, so they cannot execute ETc.

## Source → claim → parameter → proposed rule

Every populated profile parameter identifies exact claims, original units and
statistics, temporal/spatial support, method, uncertainty and limitations. Claims
resolve to primary/supporting sources with exact locators and publication/retrieval
precision. Identity facts have separate taxonomic claims. All claims retain
`reference_only` review, including manually checked official facts.

```sh
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/knowledge.py export-v03 \
  rice.mm.calendar-5-sessions-0@1 --region MM-FAO-AEZ-001 --system rainfed_lowland
```

The `profile` output uses v0.3's exact wire shape, reference review, no candidate
approval and **zero rules**. The `sidecar` retains the crop, full profile,
claims/sources, catalog SHA-256 and every blocked conversion. Pass only `profile`
to Rust; retain the sidecar for inspection. This is a new standalone adapter;
7N's existing v1-only `Catalog` loader intentionally does not load this schema.
See [the exact integration handoff](../../../docs/integration/7p/HANDOFF_7N.md).

## Rotations and honest unknowns

The eight requested sequences preserve declared order. The sesame-to-pulses
example explicitly uses mung bean as an illustrative pulse identity. Rice/pulse,
rice/sesame, rice/groundnut and wheat/sorghum/fallow have bounded published order
or system context. Other exact pairings/order/local conditions remain research
questions, with general references only where supported. Tradeoffs, fallow
requirements, field drainage, water adequacy and actual crop history remain
unknown; no ranking, percentages, N credits or pest/yield/income scores exist.

**Every example date is synthetic software input**, not an extracted or recommended
planting date. The fixture's point `(0,0)` and field ID are invented solely to
exercise the source-independent calendar contract. Fallow is a separate explicitly
dated synthetic history interval, never a fabricated crop or inferred complete
farm history. Rust checks known chronology while crop criteria stay unknown;
software-test summaries remain insufficient even when a calendar conflict is
demonstrated.

## Rebuild and verify

```sh
/tmp/earthsync-crop-v2/bin/python data/crop-knowledge/v2/tools/build.py --check
/tmp/earthsync-crop-v2/bin/python -m unittest discover -s data/crop-knowledge/v2/tests -p test_offline.py -v
/tmp/earthsync-crop-v2/bin/python -m unittest discover -s data/crop-knowledge/v2/tests -p test_scientific.py -v
cargo build --locked --manifest-path engine/Cargo.toml --example v03_demo
/tmp/earthsync-crop-v2/bin/python -m unittest discover -s data/crop-knowledge/v2/tests -p test_rust_contract.py -v
```

`build.py` without `--check` intentionally regenerates outputs and integrity hashes;
it cannot bypass the separately pinned original-byte manifest. `--check` writes
nothing and detects generated drift. Stored hashes establish byte integrity, not
scientific truth. Expert review and future accepted rule work remain separate.

Live tests are explicitly separate and require `EARTHSYNC_LIVE=1`; offline CI
does not count them as passed. To collect one new source receipt into a **new**
local directory without changing the package:

```sh
python data/crop-knowledge/v2/tools/capture.py data/crop-knowledge/v2/retrieval-plan.json \
  /tmp/earthsync-new-source-capture --source ecocrop_rice
EARTHSYNC_LIVE=1 /tmp/earthsync-crop-v2/bin/python -m unittest discover \
  -s data/crop-knowledge/v2/tests -p test_live.py -v
```

Historical retrieval plans preserve a rejected wrong GRIN species and an
unavailable SoilGrids README URL; do not repeatedly retry those entries. New
captures are pending rights/content review and never auto-import or grant review.
The initial capture batch recorded request start and retrieval day, but not exact
response-completion instants; receipts state that limit instead of inventing
timestamps. Later captures record both instants. Full non-redistributed responses
are represented by hashes/receipts, not claimed as offline original bytes.

The optional `tools/soil_probe.py` uses the **unchanged existing 7I** locked server
environment, once per bounded query. The recorded WCS transport succeeded but
its raster lacked explicit nodata and was rejected. It is not a passed numerical
soil integration; REST stays paused and no zero/default soil values are emitted.
GAEZ v5 has an actual lightweight official metadata importer; numerical spatial
extracts remain unintegrated. No huge raster archive is downloaded.

See [verification](../../../docs/integration/7p/VERIFICATION.md),
[7J handoff](../../../docs/integration/7p/HANDOFF_7J.md) and
[scientific limitations](../../../docs/integration/7p/SCIENTIFIC_LIMITATIONS.md).
