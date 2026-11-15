# Crop knowledge v1 — proposal for 7E

Status: **proposed_pending_7e_review**. This is a 7G-owned offline data contract,
not the Rust `analyze_v03_json` request, and not an amendment to v0.2. No engine,
Flutter or production backend consumer is installed by this change.

The version marker is `earthsync.crop-knowledge.v1-proposal`. IDs are stable
lowercase identifiers; crop identity is separate from the region/system profile.
Fallow has `kind: fallow` and `crop_id: null`, never an invented crop identity.
Catalog content version `0.1.0` is independent of the schema version. A breaking
shape change needs a new schema/version and owner review.

The small boundary is:

```text
profile { id, crop_id?, kind, production_system, pilot_id, cultivar?,
          review_status, parameters, unknown_properties,
          recommendation_eligible: false, review, coverage_limits }
parameter { state, value?, unit, claim_ids[], review_status, uncertainty, reason? }
claim { id, source_id, locator, parameter_keys[], evidence_kind, review_status,
        pilot_ids[], production_systems[], spatial_support, temporal_support,
        summary, limitations[] }
source { id, url, publisher, authors[], title, version, publication_date?,
         publication_date_precision, attribution, snapshot_policy, rights_note }
```

`catalog.schema.json` is the executable JSON Schema (Draft 2020-12). The Python
validator also enforces unique IDs, resolved citations, parameter/claim linkage,
pilot/system scope, review status, calendar validity and unavailable values.
`catalog.json` is a deterministic bundle; its four source inputs are documented
in the README. Unknown fields are rejected. Missing required properties are
errors; an unavailable fact is a present object with `value: null`, no claims,
and a reason. `not_applicable` is reserved for documented inapplicability (such
as fallow taxonomy), never an automatic pass.

7E review decisions requested:

1. Agree an explicit mapping from the system IDs in the schema to engine v0.3
   types. In particular, dryland winter wheat, irrigated soybean and drill-sown
   delayed-flood rice cannot silently collapse to an older `upland`/`lowland`
   enum. Until agreed, no exporter or v0.2 conversion is supplied.
2. Preserve the complete claim/source graph, individual review status, nulls,
   date precision, regional support and conditions. An empty claim pilot/system
   list means that the reference itself does not assert that scope; taxonomy or
   a general method must never certify regional agronomic applicability.
3. Keep `reviewed` as **source desk review of that fact**, not
   `verified_for_supplied_context`, independently reviewed agronomy, or permission
   to generate scenarios. `recommendation_eligible` remains false for this pack.
   All eight profiles have material gaps. Synthetic evidence cannot enter them.
4. Treat calendar entries as advisory month/day guidance, including a nullable
   start or end. They are not hard permitted-date constraints, do not supply a
   year, and cannot imply harvest dates or durations. Cross-year windows must
   explicitly say so. Do not inherit PR #11's index-to-month assumptions.
5. Keep **soil** temperature, its unknown measurement depth and warming/forecast
   conditions intact. NASA POWER monthly T2M is not an interchangeable input.
   `soil_depth_cm` is unavailable: a historical two-inch temperature reference
   is retained in a claim, without promoting it to a rooting-depth requirement.
6. Consume published guidance/research/taxonomy as reference knowledge, distinct
   from observed, modeled, forecast, farmer-reported and synthetic environmental
   inputs. The pilot fixtures contain no environmental values or confirmed farms.

Review disposition: pending 7E owner acknowledgment. The draft PR is the review
surface. This file does not claim acceptance or independently change an engine
interface. `tests/test_catalog.py` supplies producer contract and rejection tests;
cross-component serialization tests belong in a jointly agreed follow-up.
