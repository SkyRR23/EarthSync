# Confirmed defects

Severity describes potential scientific impact, not a security rating. Reproduction
inputs are explicitly fictional NASA-shaped responses or synthetic Rust fixtures.
They establish software behavior, not field accuracy. No archive-derived live
workflow was enabled.

| ID | Severity | Version and trigger | Before | Repair and scope |
| --- | --- | --- | --- | --- |
| J01 | High | Final 7H `PowerProvider`; valid metadata/time series with missing, swapped or unrelated provider point | Response accepted and labeled with requested coordinates | Validate finite GeoJSON Point coordinates against query, allowing only observed three-decimal serialization quantization (0.0005 degrees plus roundoff), including optional elevation. Preserve returned geometry as regional grid context. |
| J02 | High | Final 7H; two JSON values for the same daily key | `json.loads` silently kept the last value, concealing source conflicts | Reject duplicate keys at every JSON object level, including identical duplicates. |
| J03 | Medium | Final 7H; complete calendar plus `20240230`, `20241301`, outside-year day or `ANN` key | Extra source records silently ignored; invalid dates could survive beside apparently complete data | Reject keys outside the actual requested Gregorian day set. Absent expected dates remain explicit missingness. |
| J04 | Medium | Final 7H; accepted provider response | Header/query/geometry retained but no exact response-body identity | Include SHA-256 of complete decoded HTTP response bytes in each source-request sidecar. This does not retrospectively recover old raw responses. |
| J05 | High | Current Rust v0.3 at PR #18, final 7H and the engine pinned by 7I; regional crop/fallow history with a region-wide succession rule and a confirmed farm | `test.succession` returned `supported_by_supplied_evidence` for regional history as though it established that farm's predecessor/fallow | Require exact confirmed-field history for predecessor and fallow selection independently of the rule's regional applicability. No schema changes. |
| J06 | High | Current 7I daily provider; precise farm point such as 42.030234 N, -93.620234 E | Its 1e-6 degree comparison rejects a matching POWER response serialized to three decimals | Separate tested 7I patch and regression supplied under `patches/`; allow half a 0.001 degree serialization step plus roundoff. Keep query and returned geometry distinct. |

J01–J04 are already handled by 7I's independent daily provider: geometry and
calendar key checks, duplicate JSON rejection and exact response hashes exist
there. They still affect the default final-7H monthly demonstration path.
J05 is a latent engine defect; the shipped reference-only catalogs have no
executable succession rule, and 7I leaves history unreviewed/incomplete. Those
guards prevent this reproduction from becoming a current crop recommendation.

## Exact reproductions

`server/tests/test_science_audit.py` constructs 60 daily records for January and
leap-February 2024. January rain is 1 mm/day and temperature 10 C; February rain
is 2 mm/day and temperature 20 C. Correct totals are 31 and 58 mm. Mutations
exercise J01–J04 independently. On the pinned unpatched 7H source, **15 cases
failed and one missingness control passed**. After the patch those 16 and two
additional coordinate-precision/boundary regressions pass.

`engine/tests/science_audit.rs` starts with the existing explicitly fictional
v0.3 fixture, keeps the confirmed farm, and changes only the preceding crop's
or fallow interval's spatial support to the matching region. On unpatched
v0.3, **two regressions failed with actual SupportedBySuppliedEvidence instead
of InsufficientInformation**; five controls passed. After the fix all seven pass.

The fix preserves region-wide rule applicability. It changes what evidence can
establish field occupancy; a regional rule is not evidence of regional history
being true of one farm. Different-field and missing-field evidence remain
unusable for that purpose.

The live precision probe in `evidence/precision/` queried 16.851234 N,
96.151234 E and received 16.851 N,96.151 E. Its complete original body hash is
`22d057290c5dd9a96159f2eb35985317558e445efd8b844b521ee82e71287b93`.
The initial 7J guard was too strict as well; that was corrected before accepting
the final repair. A full leap-February request at that precise point now succeeds
through the patched 7H provider, with original query, actual returned point,
retrieval time, response hash and daily completeness retained in the receipt.
This verifies association with serialized provider coordinates, not farm accuracy.

`patches/7i-power-coordinate-precision.patch` supplies J06's isolated provider
change and two tests. Against the exact unpatched 7I export, the high-precision
test fails with `SPATIAL_MISMATCH`, and its neighboring-point rejection control
passes. In a separate exact export with this patch applied, **85 platform tests
pass with three explicit live-provider skips**, using 7I's original pinned engine.

## Remaining contract limitations

Rust v0.3 provenance carries an issue **date**, but no trusted forecast model/run
identity or subdaily run timestamp. Its generic `reviewed` flags are caller
assertions, not independent source acceptance. Final 7H's weather adapter marks
unverified model runs unavailable; 7I's orchestrator accepts the pinned modeled
POWER lineage only. Preserve those gates. Do not represent generic Rust forecast
arithmetic as source-verified live forecast acceptance. A future verified forecast
interface needs explicit model/run/version/time identity and a reviewed adapter.

The new archive has passed its complete checksum gate and full inventory.
Its separately confirmed historical defects and negative regressions are in
[ARCHIVE_FINDINGS](ARCHIVE_FINDINGS.md); they were not presumed to persist in v0.3.
