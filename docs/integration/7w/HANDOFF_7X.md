# 7W → 7X integration handoff

7W is an isolated worktree at `/workspace/EarthSync-7w`, branch
`feat/earthsync-crop-water-advisor-v1`, originally based **exactly** on completed
7P `940a8aad62da8b188cdd3af4d200f353d907997a`. Its draft PR targets
`data/earthsync-crop-evidence-v1`. Frozen 7N is
`a6dd13213d629e6714575425169530c617cbffad`.

No merge, history rewrite, public deployment, Android/Gradle milestone, new crop
suitability engine or agricultural rule promotion was performed. The local Web
application remains the delivery target. See [startup](LOCAL_WEB.md),
[science](SCIENCE.md), [coverage](COVERAGE.md) and [verification](VERIFICATION.md).

## Source dependency matrix

The machine-readable [full matrix](source-dependencies.json) retains each original
PR/branch/SHA, 7N component pins, 7P base and the new 7V review pin.

| Dependency | Exact source | Consumer boundary |
|---|---|---|
| 7N #24, final integrated foundation | `a6dd13213d629e6714575425169530c617cbffad` | Existing Flutter navigation/map/charts, private APIs, ownership, SQLite, photos, history and recovery retained |
| 7P #25, crop evidence | `940a8aad62da8b188cdd3af4d200f353d907997a` | Unchanged 708 identities / 75 profiles / 40 sources / 937 claims / eight ordered reference scenarios; original `load`, `lookup`, `project` interfaces |
| 7V #26, independent automated scientific desk review | `5ffe71e45f0f141d0e383cd437ab35c843960dc6` | Bounded blocked-review derivative, source-package hash and inspected-file receipt; full package is a separate 7X integration dependency; all 60 candidates blocked |
| 7J #22, scientific audit | `7b27699f13c94461a9d3d6596c47debfcfb9fed6` | Existing precision, source/day/product, missingness, quarantine and no-recommendation safeguards |
| 7I #19, evidence platform | `b578a6df2764479ff9c9df006cc00e5ddb3ccfa3` | Bounded transport/jobs, owned immutable evidence, source integrity, local-only API and actual Rust subprocess |
| Rust v0.3 #18 | `6f7f81077bbc3709c6206b0a77cf1ff4db15a982`, corrected in 7N | Existing crop/calendar/ETc algorithms and wire contract retained; a separate environmental method uses the same executable |
| v1 crop knowledge #15 | `c4112d2d2b69590b8a1e4b8118567635f08a866f` | Existing v1 loader/catalog untouched; never redirected to v2 |
| Farmer assistant #14 | `db42b9620932ed49b71a159e0eb9a61375fa3eec`, integrated in 7N | Existing deterministic retrieval with additive persisted-water/reference explanations |
| Private photos #16 | `d5e24f3a6120e745a63394a6ca1e0b28c75794c1`, integrated in 7N | Sanitization, token boundaries and separate stores unchanged; no private-store migration |
| 7H #20, Web integration | `a7c33cc6b58703501bbba0ceba1bad1d6d42004b` | Web host and existing services preserved |
| 7L #21, Flutter UI | `bd8d245b0eae92aab353d852baf05adba5527384` | Responsive existing shell; new farm evidence panel |
| 7Q #23, operations | `ef9a67ced98c9af98d677a679c9ab1761dc8904a` | Backup/restore and release validation retained; v2 files included in isolated platform runtime/artifact hashes |

## Working pathway

1. Farmer confirms a global point/name and declares a production system, then
   explicitly persists the farm revision to the local platform.
2. A historical water job fetches seven separate actual POWER parameters under
   `power-fao56-inputs.v1`. The original three-variable daily workflow still works.
3. Provider guards preserve requested/returned geometry, each product's support,
   dates/LST, definitions/units, response hashes, retrieval and missingness.
4. The hash-pinned compiled Rust calculates FAO-56 daily reference ET0 and complete
   rainfall totals. Inputs/intermediates and partial/missing outputs persist in an
   immutable evidence record with parent evidence and executable hashes.
5. Farmer explicitly selects saved snapshots and an optional v2 reference profile
   or ordered sequence. Only the exact 7P `profile` object enters Rust; original
   claims/sources/limitations and 7V findings stay in separate sidecars.
6. Rust returns actual calendar/sequence findings, agricultural unknowns and no
   recommendations. SQLite retains the full assessment, evidence and water gaps.
7. Flutter renders the saved values; the deterministic assistant explains the same
   persisted totals, growing-period references and Rust explanations with citations.

Reference examples retain synthetic dates and are never automatically installed as
farm plans. User-entered dates are proposals/reports, not accepted planting advice.

## Additive contracts to retain in 7X

| Contract | Change / compatibility |
|---|---|
| `POST /api/platform/v1/water/jobs` | Existing owned job model and historical query; 202 then bounded status polling. Source outages stay explicit gaps; mutations are not replayed. |
| `GET /api/platform/v1/crop-references?q=…` | Exact 7P lookup and optional region/system/cultivar filters; ambiguity/unavailable preserved; original sources/claims plus separate 7V blocked-review metadata. |
| `AssessmentInput.catalog_version` | Optional `v1` default; explicit `v2` selects the bounded new adapter. Existing v1 requests remain valid. |
| Assessment response | Adds `environmental_metrics` and separate null/required-input `water_findings`; `catalog_projection` retains original 7P sidecars plus `rule_review`. |
| Assistant context | Adds optional `reference_facts` (bounded growing-duration records) and optional decision `explanation`; absent explanations are omitted to preserve existing 7N response behavior. Water intent/metric is additive. Schemas/fixtures updated. |
| Native executable | Existing `--stdin` v0.3 behavior unchanged; `--water-stdin` uses versioned `fao56-daily-pm.v1`. Pin and run the newly built executable; an old binary cannot provide this method and must fail validation. |
| Packaging | Keep the whole v2 directory readable; include `platform_v1/rule_review.json`. Docker/runtime copies and package-data declarations include the new artifacts. Private APIs stay loopback-only. |

No `Profile`, `Rule`, daily-series or v0.3 crop-request schema field was added.
For v2, `pilot_id` selects the exact reference-profile scope only. It does not
establish the farm's region: Rust context `region_id` stays null and POWER retains
`power-query-context` regional support alongside its actual coordinates. A future
accepted regional rule needs an independently verified farm-to-region mapping.
There is no second ETc calculation in Python or the assistant. Derived ET0 is
projected as the existing `et0` / `mm_per_day` daily variable with method metadata.

## 7V findings and FAO-56 stage interpolation

7V was fetched and inspected at the exact requested SHA, not merged. Its package
and native tests were run from an immutable temporary snapshot against current
7W Rust: 32 passed. The source package hash, handoff, matrix, scientific review and
method-file hashes are recorded in `evidence/7v-review-receipt.json`.

The application exposes a bounded review derivative in `rule_review.json`. It is
not an executable registry; startup validation rejects any enabled/approved
candidate in it. It records all 60 blocked dispositions and the outstanding
crop-specific applicability evidence. 7P's dataset, all empty rules and false
eligibility flags remain unchanged.

FAO-56 Eq.66 keeps initial/mid Kc constant and interpolates development/late Kc
linearly. 7V's published Example 28 checks reproduce the method; its hypothetical
100-day ET0=5 mm/day example gives **synthetic** ETc 358.50 mm. Four constant
endpoint stages instead give 381.00 mm and do not preserve the method. Neither
number is an observed crop water requirement or a locally approved curve.

For 7X, no native wire change is needed if a **separately accepted, versioned**
curve is compiled into one existing constant interval per day and consumed by
unchanged v0.3 ETc. That future compiler must define establishment/day-offset and
endpoint conventions, stage coverage, locality/cultivar/system, initial wetting,
height/wind/humidity adjustments, harvest endpoints and traceable review evidence.
It must reject missing or inconsistent stages; a successful import or test cannot
approve the curve. Do not create four constant development/late endpoint stages.

If 7X instead adds native piecewise-linear stages, that requires an explicit new
contract/version, validation, fixtures, Python/Flutter/FRB schema changes and
numerical regression review. Do not add unknown fields to v0.3 profiles.

The official HTML sesame Table 11 stage row sums to 110 while stating total 100;
conversion remains blocked. Maize/sweet-corn and mung/Penauk identities remain
unresolved. No paddy coefficient transfers to upland rice, no annual rain becomes
seasonal crop rain, no family becomes a nitrogen credit, and no date gap proves
fallow. The eight independent applicability gates in 7V remain prerequisites.

## Integration strategy and unresolved scope

Keep 7W draft and initially based on 7P. Review 7N → 7P → 7W as an ancestry stack;
7V is a separately reviewed sibling of 7W above 7P. On an approved final 7X
integration branch, include the accepted 7N/7P foundation, then accepted 7W changes
and the accepted full 7V review package. Reconcile the pinned review derivative
with that package explicitly. Retarget the 7W PR only after its dependency is
accepted into the chosen integration base and the remaining diff is reviewed.
Do not rewrite or auto-merge #24, #25, #26 or main, or cherry-pick duplicate 7P data.

P0's accepted historical subset is functional. Unsupported source products,
frost-phase conversion and low-radiation method domains stay explicit gaps.
P1 remains: accepted bounded soil samples/field tests; guided soil/photo and wider
land-use/management entry; independently accepted crop curves and field water
balance; issued warnings and additional numerically validated layers. P2 remains:
calibrated crop/yield models, AquaCrop, automated imagery interpretation,
economics, public identity/hosting and large raster pipelines. These are not
represented as completed features or zero-valued outputs.
