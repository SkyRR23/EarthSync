# Sources, retrieval and attribution

The original v2 catalog remains unchanged: 937 source-linked claims, including
708 crop identities and 75 scoped reference profiles. The 27 bounded 7V facts
add reviewed FAO-56 methods/stage examples, irrigation sensitivity and Myanmar
handbook context. One new Iowa maize sampling-context fact makes 965 records.
These are reference records, not 965 approved agricultural constraints.

Original institutional sources include FAO ECOCROP, FAO Crop Calendar, FAO-56,
FAO's Myanmar handbook, Myanmar extension material, IRRI and NSW sources already
reviewed by 7P/7V. Mirror taxonomy remains labeled as mirror transcription with
unresolved taxonomy/local applicability. Source metadata, original locators,
publication/retrieval precision, scope and rights travel with retrieved claims.

Fresh investigation on 2026-11-15:

* FAO's [ECOCROP overview](https://www.fao.org/geospatial/data-and-tools/data-portals/ecocrop/en)
  confirms historical global descriptors, annual precipitation and discontinuation
  around 2015. This provides no new field applicability approval.
* [GAEZ](https://gaez.fao.org/) returned no readable source content through the
  research browser. No new GAEZ numerical threshold was imported.
* Gentry Sorenson, Iowa State University Extension and Outreach,
  [Taking Good Soil Samples, the First Step in a Good Fertilizer Decision](https://crops.extension.iastate.edu/post/taking-good-soil-samples-first-step-good-fertilizer-decision),
  2024-10-07: inspected the original article and retained one short attributed
  factual paraphrase about Iowa corn/soybean sampling depth and calibration.
  Region `US-IA`; cultivar and production system unspecified. Six inches stays
  inches and is not confused with the SoilGrids 0–5 cm layer.
  Fresh HTTP body SHA-256:
  `7bf170232f2221275deca0ad8d1e1b4e2e379a0051eafd96a005a8d65adc5f38`.

New selected metadata/claim: `server/earthsync/research/additional_evidence.json`.
No full article, photographs, logos, GAEZ rasters or new source bulk content is
redistributed. Existing files retain 7P/7V's original licensing/attribution notes.
The Iowa article permits attributed verbatim republication; other uses require
author permission. This package links the source and retains a factual paraphrase.

Example: `{"crop":"maize","region":"US-IA","question":"soil sampling"}`
retrieves `research.maize.iowa_sampling_depth` with source `isu_sampling_2024`.
`{"crop":"rice","cultivar":"unreviewed cultivar"}` returns no matching scope,
not guessed applicability. Sesame's 110-day stage sum versus stated 100 days,
maize identity and mung/Penauk conflicts remain visible in review dossiers.

Retrieved text is untrusted data. There is no instruction execution, tool call,
URL fetching or approval mechanism in retrieval. Invented claim/source IDs,
changed locators and altered retrieved records are rejected. No source ranges
are averaged or silently reconciled.
