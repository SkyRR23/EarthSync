# GEOS-IT lineage extension — proposal, not enabled

The implemented climate adapter continues to accept only `sources:["MERRA2"]`.
This document proposes a small `1.1-proposal` envelope for joint backend/Flutter
and engine-owner review. No existing consumer or scientific algorithm changes.

## Verified source evidence, 14 November 2026

The official [POWER meteorological-source documentation](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/)
returned HTTP 200 during this task. It describes GEOS-IT as a near-real-time
continuation using the same nominal grid as MERRA-2, with differences including
surface rain-gauge normalized precipitation. GEOS-IT is overwritten as MERRA-2
becomes available. The documentation recommends historical analysis ending behind
near real time; that guidance is not a guarantee of response lineage for any
particular date. The provider response must remain authoritative.

A real HTTP request at the public Iowa validation point (42.03 N, -93.62 E),
1–31 October 2026, returned 200, API v2.10.3, `sources:["GEOSIT"]`, LST,
`T2M:C` and `PRECTOTCORR:mm/day`. The adapter correctly returns 502
`UPSTREAM_SOURCE_CHANGED`. The exact raw capture and its companion metadata are
in `server/tests/fixtures/nasa_power_iowa_202610_geosit_live.*`; the metadata
records the request, response-completion timestamp and SHA-256 of both capture
and retrieved official HTML. It is modeled regional context, not a farm record.

## Proposed compatibility boundary

Keep `1.0-proposal` behavior unchanged. A new, explicitly requested version would:

- Preserve every original source list, per-request header, retrieval timestamp,
  query interval, geometry, units, fill sentinel and messages.
- Add `provenance.lineage` with `state` (`homogeneous` or `mixed_unresolved`),
  exact provider source identifiers and supporting request intervals. Do not
  infer per-day lineage from a multi-source header or a guessed cutoff date.
- For homogeneous GEOS-IT only, label `product` and seasonal metadata `dataset`
  explicitly as GEOS-IT, retaining `data_kind:"modeled"`, published units,
  spatial support, coverage and rate × duration conversion. Do not equate
  precipitation processing or scientific quality with MERRA-2.
- Reject mixed/unresolved series until official metadata provides enough
  attribution and owners agree on aggregation across source changes. A
  hypothetical daily cutoff is not an acceptable workaround.

Example lineage object (schematic contract, not downloaded scientific data):

```json
{
  "state": "homogeneous",
  "provider_sources": ["GEOSIT"],
  "attribution_basis": "single-source response header",
  "revision_policy": "provider may replace recent GEOS-IT values with MERRA-2"
}
```

The current Flutter parser requires both `schema_version:"1.0-proposal"` and
`dataset:"POWER daily meteorology / MERRA-2"`; it would reject this extension.
Rust's current seasonal metadata permits descriptive dataset strings, but
support must be checked with its owners, especially v0.2 attribution rules.
Do not rename existing fields or inject provenance sidecars into Rust structs.
A version-selection mechanism, Flutter parser support, cache partition by
contract/lineage and source-change presentation need owner agreement before
implementation. No additional API version is exposed by this patch.

## Required acceptance tests before enabling

1. Existing MERRA-2 captures produce byte-compatible environment fields under
   v1.0 and the same Rust totals; unsupported lineage still fails in v1.0.
2. Independently captured homogeneous GEOS-IT retains its exact source label,
   units, interval, modeled status and spatial support through Flutter and Rust.
3. Mixed headers, absent lineage and inconsistent annual chunks fail closed;
   no guessed daily source attribution or synthetic substitute is emitted.
4. Missing days stay null independently by variable. Rate-to-total tests cover
   leap/nonleap months and signed Celsius without invented confidence or scores.
5. Upstream revision from GEOS-IT to MERRA-2 cannot reuse a mislabeled cached
   envelope or silently overwrite the provenance of an earlier saved result.

The supplied real GEOS-IT capture already has a regression test proving rejection
under the current contract. It is evidence for joint extension work, not approval
of agronomic use or implementation of the proposed version.
