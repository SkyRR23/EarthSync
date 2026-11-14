# Confirmed defects

Severity describes potential scientific impact, not a security rating. Reproduction
inputs are explicitly fictional NASA-shaped responses or synthetic Rust fixtures.
They establish software behavior, not field accuracy. No archive-derived live
workflow was enabled.

| ID | Severity | Version and trigger | Before | Repair and scope |
| --- | --- | --- | --- | --- |
| J01 | High | Final 7H `PowerProvider`; valid metadata/time series with missing, swapped or unrelated provider point | Response accepted and labeled with requested coordinates | Validate finite GeoJSON Point coordinates against query within 1e-6 degrees, including optional elevation. Preserve returned geometry as regional grid context. |
| J02 | High | Final 7H; two JSON values for the same daily key | `json.loads` silently kept the last value, concealing source conflicts | Reject duplicate keys at every JSON object level, including identical duplicates. |
| J03 | Medium | Final 7H; complete calendar plus `20240230`, `20241301`, outside-year day or `ANN` key | Extra source records silently ignored; invalid dates could survive beside apparently complete data | Reject keys outside the actual requested Gregorian day set. Absent expected dates remain explicit missingness. |
| J04 | Medium | Final 7H; accepted provider response | Header/query/geometry retained but no exact response-body identity | Include SHA-256 of complete decoded HTTP response bytes in each source-request sidecar. This does not retrospectively recover old raw responses. |
| J05 | High | Current Rust v0.3 at PR #18, final 7H and the engine pinned by 7I; regional crop/fallow history with a region-wide succession rule and a confirmed farm | `test.succession` returned `supported_by_supplied_evidence` for regional history as though it established that farm's predecessor/fallow | Require exact confirmed-field history for predecessor and fallow selection independently of the rule's regional applicability. No schema changes. |

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
failed and one missingness control passed**. After the patch all 16 pass.

`engine/tests/science_audit.rs` starts with the existing explicitly fictional
v0.3 fixture, keeps the confirmed farm, and changes only the preceding crop's
or fallow interval's spatial support to the matching region. On unpatched
v0.3, **two regressions failed with actual SupportedBySuppliedEvidence instead
of InsufficientInformation**; five controls passed. After the fix all seven pass.

The fix preserves region-wide rule applicability. It changes what evidence can
establish field occupancy; a regional rule is not evidence of regional history
being true of one farm. Different-field and missing-field evidence remain
unusable for that purpose.

## Remaining contract limitations

Rust v0.3 provenance carries an issue **date**, but no trusted forecast model/run
identity or subdaily run timestamp. Its generic `reviewed` flags are caller
assertions, not independent source acceptance. Final 7H's weather adapter marks
unverified model runs unavailable; 7I's orchestrator accepts the pinned modeled
POWER lineage only. Preserve those gates. Do not represent generic Rust forecast
arithmetic as source-verified live forecast acceptance. A future verified forecast
interface needs explicit model/run/version/time identity and a reviewed adapter.

The new archive may contain additional defects. None is claimed confirmed until
its original bytes pass the user's checksum gate and are reviewed.
