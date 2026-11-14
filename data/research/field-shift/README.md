# Field Shift environmental contribution — Milestone 5B

Audited 14 November 2026. This directory preserves the contributed pack and
contains reproducible **research fixtures**, not production adapter payloads.
The contribution has useful data, but **no new numeric series is cleared for
production integration** with its present provenance and quality metadata.

- [Source manifest](SOURCE_MANIFEST.md): providers, locations, coverage, units,
  spatial support, attribution and readiness.
- [Quality report](QUALITY_REPORT.md): confirmed defects, unresolved evidence,
  collection-script review and backend compatibility.
- [Integration plan](INTEGRATION_PLAN.md): three optional adapters and their
  release gates; no new agricultural rules.

## Preservation and evidence

`raw/field-shift-data-pack.zip` is the unchanged 345,833-byte upload, SHA-256
`f9d4eb2c5bcb6c73de5fc8bb17bc13a90241eee40715bf5522d369629b88f65c`.
`raw/original/data-pack/` contains byte-identical extracted members: 46 CSVs,
12 JPEGs, README, API notes, collection script and fetch log (62 files and five
directory entries). `archive_inventory.json` records every member's hash, size
and unverified ZIP timestamp. ZIP timestamps are not retrieval records.
Scoped Git attributes disable line-ending conversion and whitespace cleanup for
`raw/`, so an ordinary checkout preserves contributed CRLF and other bytes.

The archive passed bounded path/type/size/compression, decompression and CRC
checks before extraction. No contributed Python was imported or executed.
The raw README/API notes contain proposals and claims; preserving them does not
approve their instructions, data semantics, anomaly messages or drainage rules.
Do not run their collection commands against this immutable copy.

`provider_evidence/` contains separately identified NASA parameter-catalog
captures made during this audit. These verify catalog units, not the missing
original retrievals. The other provider documentation is linked and review-dated
in the source manifest. Original provider JSON/HTML bodies are absent from the
contribution; extracted CSVs are already processed by its author.

## Outputs and reproduction

Use Python 3.11+ (standard library only), from the repository root:

```sh
python data/research/field-shift/scripts/inspect_zip.py data/research/field-shift/raw/field-shift-data-pack.zip
python data/research/field-shift/scripts/normalize.py
python -m unittest discover -s data/research/field-shift/tests -v
git diff --check
```

The inspector is read-only and never extracts or executes a member. The
normalizer is offline, reads only the preserved CSVs/log and writes four files
under `normalized/`. To compare without replacing those outputs, use
`normalize.py --output /tmp/field-shift-normalized`.

`normalized/{hlegu,bago,magway}.json` retain 32 modeled soil properties/depths,
four historical MODIS series, and 16 forecast dates per location. Each source
has a relative raw-file link and SHA-256; records link to original CSV row
numbers (header is row 1). Candidate fetch-log row numbers refer to the preserved
log. They are not authenticated response-to-output links. Unknown issue times,
release identifiers, uncertainty and QA remain null, with explicit reasons.

`normalized/audit_inventory.json` inventories every CSV's columns, inferred
types, blank counts, numeric ranges and date coverage, and all failed log row
numbers. Blank optional notes are counted separately from scientific missingness
in the quality report. Generated JSON rejects nonfinite numbers.

The vocabulary is `observed`, `modeled`, `forecast`, `hypothetical`,
`farmer_reported`, `unavailable`. Here `observed` means a satellite-derived
retrieval/index, never a direct farm observation. SoilGrids is `modeled`;
outlook values are `forecast`; absent cells are `unavailable`. There are no
farmer reports or new hypothetical environmental values in the research fixtures.
Test archives are hypothetical software inputs.

## Scope and disposition

**Ready:** preservation, source inventory, offline conversion/missingness test
fixtures, and adapter proposal. **Reference-only:** SoilGrids estimates,
QA-unknown historical MODIS values, archived forecast snapshots, terrain,
land-cover, CMR results, GIBS imagery and US reference examples.
**Blocked:** live weather use, crop-reference integration, inferred drainage,
current anomalies, disease claims, and substitution of this pack into POWER's
historical climate pipeline. The manifest states the remaining gates per source.

The branch starts at main `1ea3df7b09637cf8162f834411d830aa8621590c`.
Backend compatibility was reviewed read-only at
`4befe7d1e204c875436ab486c231edcbb944f317` on `feat/nasa-power-backend`.
No Rust, Flutter or production server files are changed. No environmental series recollection,
automatic merge, production deployment or agricultural suitability work is part
of this milestone.
