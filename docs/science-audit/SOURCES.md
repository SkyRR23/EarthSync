# Source inventory and reuse/rejection matrix

## Immutable pins and checksums

| Source | Exact identity |
| --- | --- |
| Final 7H / PR #20 | `a7c33cc6b58703501bbba0ceba1bad1d6d42004b` |
| 7I / PR #19 | `b578a6df2764479ff9c9df006cc00e5ddb3ccfa3` |
| 7L / PR #21 | `bd8d245b0eae92aab353d852baf05adba5527384` |
| Original v0.3 / PR #18 | `6f7f81077bbc3709c6206b0a77cf1ff4db15a982` |
| PR #11 | `a85e2dd48805a36faebfec93c6991d5babb1add2` |
| PR #11 original ZIP | `f9d4eb2c5bcb6c73de5fc8bb17bc13a90241eee40715bf5522d369629b88f65c`, 345,833 bytes |
| New original ZIP, verified | `241cdcfac1df62b7608b403e8cbcb48d0b8ba9ca9fddc8cce766279016327788`, 55,057,221 bytes |
| Restored part 03 wrapper | `953a4cea81e5f8e7afce58f8ce46102a6f458d476131f83f4b520806fa5c2ebb`, 8,388,772 bytes |

All nine retry segment wrappers/payloads, seven original wrappers/payloads, and
final original were verified using the reviewed supplied helpers and independent
hash checks. [Receipt](evidence/reassembly-verified.json). Original archive is
read-only under `/workspace/shared/downloads/`; parts/helpers remain preserved.
Earlier failed-transfer notes are historical, superseded by successful integrity.

## Complete inventory

[New inventory](evidence/contributed-inventory.json): 743 members, 600 files,
191,092,734 uncompressed bytes, 143 directories. All member bytes read, CRC checked
and SHA-256 hashed. All 50 CSVs fully parsed, including columns, row counts,
empty cells and ragged rows. All non-build JSON parsed with duplicate-key rejection.

- 487 generated `target/` files: binaries, libraries, build caches, fingerprints
  and generated metadata. All rejected; none executed or copied into the source build.
- 113 non-build files: 14 Rust files including CLI/tests; two Python scripts;
  six original POWER response JSONs and six URL sidecars; field/crop/rule/location
  contracts and two example JSONs; three methods/dictionary/budget documents;
  authoring/data CSVs, README/API notes, logs, config/lock metadata and 12 JPEGs.
- 60 exact PR #11 matches: collector, all 46 environmental CSVs, fetch log,
  and 12 JPEGs. README and API notes changed. New crop CSVs, raw responses and
  source artifacts are separately inventoried; PR #11 did not contain them.

The original source/data extraction excludes all build output and is sealed
read-only. Every one of its 113 files was rehashed unchanged after review.
Documents and code were treated as evidence, not instructions. Source/helper
execution was limited to explicitly reviewed and authorized reassembly, fresh
source compilation/tests, and the builder's pure offline functions; the collector
and builder main were not run. No original precompiled artifact was trusted.

## Reuse and rejection decisions

| Family | Finding | Decision |
| --- | --- | --- |
| Six raw POWER JSONs + URL sidecars | Original units, header, geometry, lineage and dates exist; original retrieval receipts absent | Preserve/hash for research. One current provider repeat matches all 390 Hlegu baseline precipitation values; that is not authentication of all records, proof of product-instability cause, or farm validation. |
| POWER flattened climatology | FEB ordinal 1 through ANN ordinal 12 | Reject import; lost January cannot be reconstructed from ANN. |
| POWER monthly/daily CSVs | Monthly rainfall is mm/day; daily row-count and missingness claims flawed | Research only. Complete exact-calendar conversion is separate and preserves missing year-months. |
| Generated field contexts | Modeled data called observed, unsupported statistical labels/build timestamps, incomplete-sample averaging possible | Reject as executable/live context. New rainfall fixture is explicitly modeled, reference-only and calendar-complete. |
| SoilGrids | Four depths/means; WMS map pixel, native footprint and uncertainty not established | Conversion checks only; reject field measurement, drainage/root-zone or temporal observation claims. |
| MOD11A2 LST | 206/552 missing; QA absent; 65535 discarded as universal fill | Retained numeric scaling can be checked. Reject accepted air-temperature, clear-sky count and usable-pixel claims. |
| MOD13Q1 NDVI/EVI | Composite starts complete; VI QA and current numeric anomaly baseline absent | Reject crop-health/anomaly/disease claims. Record coverage is not quality. |
| Open-Meteo current/archive/forecast/GloFAS | Current modeled, missing original time/run metadata, incomplete forecast soil columns, archive 364 rows | Research snapshots only; no fresh forecast, irrigation or field flood acceptance. |
| CMR/landcover | Magway outside bbox; one catalog result; mixed landcover pixel | Discovery/context only, not crop identity or field coverage. |
| Terrain/US reference | Coarse terrain/US component context | No Myanmar field soil observation or measured field slope inferred. |
| Myanmar profiles/ECOCROP | 12 profiles; 11 directly readable original sheets plus one cached-only reference; unsupported per-parameter local claims | Preserve as quarantined reference assertions; zero executable rules or eligibility promotion. |
| Old Rust engine/rules | 13 original tests pass; 12 scientific desired-property tests fail; heuristic scores/weights/credits | Reject adoption. Reproduce only from reviewed source in a clean external build. |
| Builder/collector | Coverage, provenance, statistic and metadata defects | Static/reproduction evidence only. New independent validators repair the acceptance boundary; originals unchanged. |
| Examples/JPEGs | Example farmer input has no independently verified farmer origin; JPEGs are rendered previews | Synthetic/unverified example context and visual reference only. Never live measurements. |

## Primary provider sources

[NASA lineage](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/)
supports modeled grid context, not farm observation.
[NASA temporal processing](https://power.larc.nasa.gov/docs/methodology/data/processing/)
distinguishes extrema from mean daily extrema (`_AVG`).
[ISRIC units/depth/quantiles](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html)
supports property-specific scales and six standard depths; absent uncertainty is
not zero. [MOD11A2 specification](https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/MOD11A2)
requires band-specific fill/range/QA interpretation.
[FAO-56 equation 52](https://www.fao.org/4/x0490e/x0490e07.htm)
requires applicable temperature statistics and regional verification; its radiation
unit conversion in the archive is arithmetically correct. No stage Kc or accepted
local ET0/water-balance pipeline follows. Crop source details are in the quality report.

## Reproducibility

```sh
python tools/science_audit/audit_contribution.py ORIGINAL.zip --compare PR11_INVENTORY.json --output REVIEW_OUTPUT
```

The command rechecks the pinned archive checksum before reading any content,
inventories every member, records source metadata and label errors, and emits
reference-only quarantine records. It never imports/executes archive code.
