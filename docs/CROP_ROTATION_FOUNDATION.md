# Crop and rotation foundation — Milestone 3A

## Additive API and scope

`decision::compare_rotations(&DecisionRequest) -> Result<DecisionResult, DecisionError>`
and `decision::compare_rotations_json(&str) -> Result<String, String>` are separate
provisional entrypoints. `analyze_field`, its existing JSON, errors and twelve-month
semantics are unchanged. `seasonal` and `climate.rs` are unchanged. No networking,
new dependencies, bridge generation, crop database or backend implementation added.

This is a categorical eligibility foundation, not a recommendation engine. It
contains no built-in agricultural thresholds, numerical crop scores, yields or
water-saving estimates. No real crop profiles are shipped. Inputs are independently
testable; future P2 records will require review and mapping before integration.

## Data models and explicit unknowns

- `CropProfile.profile_id` identifies one production-system reference record;
  `crop_id` identifies the crop and may repeat across different profiles. Crop IDs
  use lowercase letters/digits/underscores; other stable IDs may also use hyphens.
  Empty or malformed identities and duplicate profile/source/scenario IDs are
  errors. Common name can be null; no name-based scientific lookup occurs.
- Nullable `Fact<T>` attributes represent documented production system, crop
  family, allowed planting months, soil texture set, drainage set and irrigation
  prerequisite. A fact carries its own source IDs. Null means unknown, not no
  constraint. Empty allowed sets are invalid; use null for unknown.
- Known production systems distinguish irrigated lowland, rainfed lowland and
  upland. `Other` preserves an unsupported input category but is never matched as
  supported. Null is the explicit unknown. Soil/drainage enums are intentionally
  limited; P2/P4 must agree mappings rather than silently coercing local terms.
- Water requirements distinguish irrigation-required from irrigation-not-required
  management only. The latter does not prove adequate rainfall or water supply.
  Unsupported quantity, climate, soil-pH, phenology or other requirements belong
  in `unsupported_requirements`, not in invented thresholds. Null means the
  requirements catalog is unknown; an empty list means no additional requirements
  were supplied, not that all scientifically relevant requirements are covered.
- `FarmerContext` carries nullable irrigation, texture and drainage inputs.
  Each `CropStep` has nullable crop/profile IDs, selected production system and
  an optional inclusive `SeasonalWindow`. Known dates use the same Gregorian
  year/month range as seasonal analysis (years 1–9999, months 1–12). Reversed or
  invalid windows are errors. Crop/season unknowns are allowed.
- `RotationCandidate` has an explicit `is_baseline` flag and ordered steps. One
  and only one baseline, at least three total scenarios, unique scenario IDs and
  nonempty step sequences are required. All input order, labels, unknowns and
  steps are returned unchanged; baseline position is not assumed to be first.
  Caller supplies the actual baseline; it is not inferred from crop names.
  Fallow can be a step with no known profile and then remains unknown; it is not
  silently treated as a supported crop or benefit.

Source records contain ID, citation, scope and status. Scope must describe the
caller-reviewed context (region, season, production system); the engine cannot
verify a citation or applicability from a string. `verified_for_supplied_context`
is the caller's assertion of review, not independent validation by this engine.
`reference_only` is explicitly unreviewed. `synthetic_test` permits testing the
categorical machinery and makes `contains_synthetic_references` true in output.
Synthetic labels and limitations MUST remain visible in any future UI/demo.
A citation's existence never establishes Myanmar applicability by itself.

## Evaluation semantics

1. Validate the entire catalog, source references, IDs and scenario structure
   before evaluation. Dangling source IDs are errors, including in unused records.
   Uncited facts are structurally valid but cannot support a decision.
2. Match the explicitly selected profile; never substitute another system for the
   same crop ID. A missing/unknown profile is insufficient information. A selected
   crop ID different from the profile ID's crop is a structural conflict.
3. Each supported categorical check needs a non-null fact, at least one source,
   and all linked sources reviewed for the supplied context or labeled synthetic.
   Any reference-only source makes the check unknown rather than positive or
   negative. Missing farmer inputs also make that check unknown.
4. Check production-system equality, allowed planting-month membership, texture
   membership, drainage membership and irrigation access when required. A window's
   start month is the planting month; the rest of the growing calendar is not
   assessed. Crop family is retained as sourced metadata; it supplies no family
   rotation rule, pest claim or soil-health inference.
5. Unsupported requirements remain missing-information entries even when sourced.
   At crop-step level, conflicts take precedence; otherwise any missing information
   means insufficient; otherwise the outcome is supported by the supplied evidence
   for the implemented categorical checks only. Unknowns remain visible alongside
   conflicts. This is not a statement that the crop is agronomically suitable.
6. Rotation results aggregate the step findings but always add the missing
   transition/duration/harvest-calendar/water-budget/soil-health rules. Thus whole
   rotations are insufficient unless a step conflicts, in which case the rotation
   has a supplied-evidence conflict. `possible_benefits` is an empty structured
   placeholder. No alternative is ranked, selected, or declared superior.

Every assessment contains structured evidence, risks and missing information,
with codes/messages/source IDs. Per-crop results retain which step caused each
finding; rotation aggregates retain the same findings. Risks describe documented
constraint conflicts, not quantified probabilities or forecasts. The top-level
source registry and synthetic marker preserve evidence interpretation.

Seasonal results are not compared to crop water/temperature bounds in 3A. Growing
windows can cross years but schedule overlap and duration are explicitly
unevaluated. The synthetic two-step example deliberately overlaps; its rotation
remains insufficient rather than pretending a calendar-feasibility test passed.

## Synthetic tests

`engine/tests/fixtures/synthetic_rotations.json` is clearly labeled software-test
reference data: fictional test crop/family, artificial categorical requirements,
and hypothetical farmer inputs. It is not a Myanmar agricultural reference or a
NASA observation. Its eligibility results only test the supplied synthetic rules.
The fixture is exercised by `engine/tests/decision.rs` through typed and JSON APIs.

Run from `engine/`:

```sh
cargo fmt --check
cargo test --locked
cargo clippy --all-targets --locked -- -D warnings
git diff --check
```

## P2/P4 decisions before live integration

1. Review PR #2 and [the contract reconciliation](TEAM_CONTRACT_REVIEW.md). Neither
   its crop payload nor this module is a frozen team schema. Decide the adapter,
   versioned endpoint and source/production-system identity mapping together.
2. P2 must supply sourced Myanmar-specific requirements and applicability, with
   explicit unknowns, review status and evidence attached to each constraint.
   Confirm how citation/license/version/region information is represented.
3. Agree planting versus growing/harvest windows, varieties and production systems,
   farmer soil/drainage vocabulary and whether observations change by rotation step.
4. P2 supplies verified transition/calendar/family/soil-health/water rules before
   we implement them. Annual rainfall alone is not irrigation adequacy; legumes
   do not automatically create a soil benefit.
5. P4 agrees baseline/alternatives, per-step explanations, unknown/conflict display,
   synthetic flags and the separate API's eventual bridge mapping. No change to
   existing analysis results until that integration is approved.
