# 7P → 7N integration handoff

Branch: `data/earthsync-crop-evidence-v1`. Isolated worktree:
`/workspace/EarthSync-7p`. Base: **`a6dd13213d629e6714575425169530c617cbffad`**,
the fetched PR #24 head. Exact PR #15/#18/#19/#20/#21/#22/#23/#24 source identities,
protected-file hashes and the delta from preparation SHA `17bf7b2` are recorded
in [source-shas.json](source-shas.json). The delta concerns the completed archive
audit/research quarantine and handoff documentation; none of its old crop rules
is promoted here.

The deliverable is `data/crop-knowledge/v2/`, standalone Python tooling and its
new CI workflow. Existing v1, central navigation, main FastAPI routers, database
migrations, Rust types/algorithms and all 7J audit evidence are unchanged. There
is no service to deploy, no new database and no automatic merge.

## Exact consumer boundary

1. Keep v1 installed as today. The existing
   `server/earthsync/platform_v1/catalog.py` accepts only its v1 schema and hash;
   **do not point that loader at v2** or relax its checks.
2. For an optional future reference UI/API, install the small pinned v2 validation
   dependency, mount the whole versioned directory read-only, call `load()` and
   expose `lookup()`. Preserve unavailable/ambiguous results, exact identities,
   cultivar/system/region filters and original source sidecars. No network is
   required after installation.
3. For an explicit engine experiment, call `project(data, profile_id, region_id,
   production_system, cultivar)`. Its `profile` is the **only** v0.3 wire object.
   Persist/display its separate `sidecar` with the exact catalog SHA, full crop,
   source/claim graph and blocked-conversion reasons. Do not send sidecars as
   extra Rust struct fields: native Rust rejects unknown fields.
4. Production-system mapping is explicit: rainfed lowland/upland → `rainfed`,
   flooded irrigated lowland → `flooded_lowland`, irrigated upland → `irrigated`,
   dryland → `dryland`. This supplies identity/system context only; it grants no
   agronomic applicability or executable requirement. Ambiguous supply systems,
   ecology-only profiles, disputed crop identities and delayed-flood transitions
   remain blocked. Full original system context stays in the sidecar.
5. All exports have `review=reference_only`, `approved_for_candidates=false` and
   `rules=[]`. Every new source/claim/profile is reference-only. Never derive an
   executable rule or candidate from the fact that a field is populated. Changes
   to these gates require separately documented independent acceptance and a new
   reviewed version, outside this package.

The fixtures exercise the **real unchanged Rust executable** with eight ordered
research scenarios and two negative schedule cases. Their dates, `(0,0)` point
and field confirmation are synthetic software inputs. Calendar comparisons can
be known; agricultural criteria and whole software summaries remain insufficient.
An explicitly dated synthetic fallow interval remains history, not a plant or
proof of complete real field history. No scenario is a recommended rotation.

## What the demo can honestly display

- Five priority crop reference views, original ecological envelopes, local
  advisory calendars, exact source/version/locator, units/statistic and missing
  parameter reasons. Mung bean and maize calendar disagreements stay visible.
- 708 agricultural identities and the full 2,568-species inclusion/exclusion
  inventory. Most extra crop species have **identity only**, not growing rules.
- 75 source-specific reference profiles, eight requested sequence examples and
  the reason every potential v0.3 rule remains blocked.
- Dataset/NASA inventories distinguishing actual inherited POWER evidence,
  imagery/reference context, discovery and unintegrated products.

Do not label these views as suitability, independent validation, farmer yield,
current local planting advice or accepted crop candidates. The schema deliberately
keeps source-backed facts, regional modeled context, requested research scopes,
synthetic examples and genuine unknowns distinct.

## Provider and rollout limits

The existing 7I SoilGrids WCS path was reused once. Both responses arrived, but
the int16 2×2 raster had `nodata=None`; unchanged 7I rejected it with
`SOIL_ENCODING_MISMATCH`. Exact tiny captures and a diagnostic receipt are
provided for a separate provider-contract review. Do not assign a sentinel or
accept numerical soil evidence in 7N on this basis. Release identity, quantiles
and effective temporal support remain unknown. REST remains documented paused.

GAEZ v5 has an actual official metadata importer and source manifest; no numerical
spatial suitability/yield extract is accepted. CMR collection access succeeded,
but no live HLS/SMAP/SAR pixels were measured. Existing POWER/QA pipelines and
their MERRA-2/GEOS-IT, day-basis, geometry and missingness guards remain authoritative.

P1/P2 work is optional after the demo: accepted bounded GAEZ products, a reviewed
SoilGrids nodata/product contract, global taxonomic reconciliation, licensed
calendar expansion and independent regional/cultivar agronomy. It does not block
the existing final-stack demo. See [verification](VERIFICATION.md) for exact local
results and [scientific limits](SCIENTIFIC_LIMITATIONS.md).
