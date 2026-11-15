# 7P → 7J scientific handoff

Reviewed source head: **`7b27699f13c94461a9d3d6596c47debfcfb9fed6`**, PR #22.
The original archive SHA remains
`241cdcfac1df62b7608b403e8cbcb48d0b8ba9ca9fddc8cce766279016327788`.
Its verified reconstruction, 600-file inventory, 113 retained originals,
12 Myanmar assertions and scientific acceptance failures are reused as audit
context. No artifact, quarantine profile or original 7J report was edited, and
the forensic audit was not repeated.

Accepted research leads reused: the original ECOCROP IDs/sheets for rice 1574,
mung 2150, sesame 1937, groundnut 2199 and maize 2175; the bounded K-State
wheat–sorghum–fallow and NSW drill-sown rice source reviews; the corrected
June 2019 World Bank report date and regional-calendar lead. The contributed old
engine, local thresholds, planting-month defaults, irrigation credits, nitrogen,
pest, finance and ranking calculations are excluded.

New **7P** evidence is separate from the historical 7J availability record:

- Five original ECOCROP sheets were fetched as exact bytes and compared with a
  pinned third-party CSV for the priority ecological fields. Field-help pages
  clarify average growing-season temperature semantics and the annual rainfall
  query's supplemental-water caveat. None becomes a local rule.
- Official FAO Crop Calendar API access confirms Myanmar coverage, six AEZs,
  111 records updated 2021-02-26 and 55 selected priority sessions. Codes 0157/0232
  mung/green-gram/Penauk discrepancies and code 0113 maize/sweet-corn naming remain
  disputed. They are not reconciled by a favorable duration or common name.
- The previously unavailable FAO handbook `cc0246en` was fetched successfully in
  7P: 2022, ISBN 978-92-5-136276-1, CC BY-NC-SA 3.0 IGO. The erect groundnut group
  duration is located at printed p. 7 / PDF p. 21 §1.3.1; lowland cropping context at
  printed p. 119 / PDF p. 133 §12.2; general cereal/groundnut pest context at
  printed p. 62 / PDF p. 76 §6.8 is explicitly secondary guidance, not an independently
  verified pest benefit. Full copyrighted/third-party material is not copied.
- Five GRIN species/family identities were checked. An initial rice URL actually
  resolved to Oryzopsis miliacea and was rejected; correct Oryza sativa ID 26077
  is independently recorded. No accession-derived climatic claims are imported.
- 7I's unchanged SoilGrids WCS parser rejected a newly reachable raster lacking
  explicit nodata. That is a provider-contract diagnostic, not a new soil value.

The new package contains separate source/claim/parameter evidence, explicit
unknowns, source-specific disagreements and blocked Rust mappings. All source,
claim and profile review remains `reference_only`; all recommendation/candidate
flags remain false and executable rule lists empty. The 708-identity global
import does not establish growing requirements, local applicability or farm
suitability. Most imported identities have no profiles.

Mechanical safeguard tests verify these boundaries, source identity/version,
scope, native units/depth, chronological order, missingness, original hashes and
promotion rejection. They do **not** constitute independent agronomist review,
field validation or experimental verification. Requested follow-up review can
use `knowledge.py trace`, `mapping-report.json`, the missing-parameter register
and source/rights inventory without replaying the archive audit.
