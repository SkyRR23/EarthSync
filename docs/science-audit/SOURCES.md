# Source inventory and reuse/rejection matrix

## Immutable source pins

| Source | Exact commit or checksum | Audited role |
| --- | --- | --- |
| Final 7H / PR #20 | `a7c33cc6b58703501bbba0ceba1bad1d6d42004b` | Branch base, actual default demonstration source and v0.3 implementation |
| 7I / PR #19 | `b578a6df2764479ff9c9df006cc00e5ddb3ccfa3` | Separate temporary source export; daily NASA provider and owned evidence/orchestration tests |
| 7L / PR #21 | `bd8d245b0eae92aab353d852baf05adba5527384` | UI ownership pin, no independent UI changes |
| Original v0.3 / PR #18 | `6f7f81077bbc3709c6206b0a77cf1ff4db15a982` | Exact compatibility engine used by 7I; compiled from repository source, never contributed binaries |
| PR #11 | `a85e2dd48805a36faebfec93c6991d5babb1add2` | Historical environmental pack, independent temporary export only |
| PR #11 ZIP | `f9d4eb2c5bcb6c73de5fc8bb17bc13a90241eee40715bf5522d369629b88f65c` | Verified 345,833 original bytes; not the newly attached ZIP |
| New `nasa_space_challenges.zip` | Expected only: `241cdcfac1df62b7608b403e8cbcb48d0b8ba9ca9fddc8cce766279016327788` | **Unverified/unavailable**, no analysis or reuse allowed yet |

The local inventory tool reads and hashes every ZIP member, verifies CRC on read,
parses all CSV records, and records paths, byte counts, columns, empty cells and
ragged rows. It performs no extraction, import or execution. Source code and
document contents are data, never instructions. It rejects ambiguous paths,
duplicate names and links. Its explicit 64 MiB/member bound fails the run rather
than silently truncating inspection. Nested archives need a separate inventory.

`evidence/pr11-inventory.json` independently matches all 62 original files to
their earlier member hashes. Inventory: 46 data CSVs, one CSV fetch log, one
Python collector, README, API notes, 12 JPEG previews, five directory entries.
No original raw provider response bodies, Rust source, executable crop profiles,
tests or Rust build artifacts exist in that old ZIP. Generated normalized files
and audit code belong to PR #11 outside its original archive.

## Available PR #11 pack decisions

| Family | Evidence found | Reuse decision |
| --- | --- | --- |
| POWER climatology | FEB ordinal 1 through ANN ordinal 12, no original response | Reject numerical normalization/live use. Retain immutable reproduction of label drift; cannot recover missing January by shifting values back. |
| POWER monthly | Ten years × twelve rows/location, mm/day rates and monthly extrema/means | Research only. A monthly mean daily rainfall rate is not a monthly total until source/statistic/calendar conversion is established. |
| POWER daily | 121 date rows/location, missing final values, original headers/lineage absent | Research only, not a complete 120-day observation series. No retrospective MERRA-2/GEOSIT assignment. |
| Open-Meteo archive/current/forecast and river discharge | 364 archive dates; modeled current snapshots; missing soil forecast values; no trusted model-run identity | Research snapshots only; unavailable for live/fresh forecast claims. Current precipitation lacks an established accumulation interval. |
| SoilGrids | Eight properties × four depths × three locations; WMS query context | Retain source codes and documented scale conversion for offline checks; reject exact farm/native-pixel, temporal measurement, drainage or root-zone claims. Depth/quantile gaps remain. |
| MOD11A2 LST | 92 composite starts per series, 206 missing values/552 positions; no QC | Valid retained scale arithmetic is testable; QA remains unknown. Reject daily air-temperature substitution and universal 65535 fill rule. |
| MOD13Q1 NDVI/EVI | 46 starts per series; no VI QA/cloud/reliability flags | Record coverage only; reject crop-health, anomaly and stress claims without applicable QA/baseline/pixel evidence. |
| Landcover/CMR | Classified subset records and a one-result catalog search excluding Magway | Context/discovery only; neither crop identity nor field pixel coverage established. |
| Terrain/US reference | Coarse grid-derived context, US SSURGO/elevation reference | Research only. US component descriptions are not Myanmar farm soil observations. |
| Fetch log/citations/collector | 522 request rows, missing POWER/weather log families; source code discards original response metadata | Preserve evidence of gaps; no collector execution or blanket source acceptance. Provider documentation cannot recreate original receipts. |
| JPEG assets | 12 rendered preview images | Visual context only, no scientific raster measurement or QA accepted. |
| Crop profiles / Rust / tests | Absent from old archive | No inference about new Myanmar profiles or contributed Rust engine. Pending new archive access. |

## Provider documents checked

[NASA POWER meteorological lineage](https://power.larc.nasa.gov/docs/methodology/data/sources_meteorology/)
identifies MERRA-2/GEOS-IT assimilation products and native grid support. This
supports modeled context and exact source checks; a query point is not a measured
farm or guaranteed returned native footprint.

[ISRIC SoilGrids units/depth/quantiles](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html)
supports separate property conversions and six standard depths. Prediction
uncertainty is not zero when quantiles are missing. The WMS map pixel does not
prove a native 250 m farm observation.

[NASA MOD11A2 collection 6.1 specification](https://ladsweb.modaps.eosdis.nasa.gov/filespec/MODIS/61/MOD11A2)
supports band-specific range/scale/QC interpretation. A discarded code cannot be
reconstructed from a blank CSV. No generic maximum-code fill rule is accepted.

## Resume the newly contributed archive

Download the **actual supplied URL** to
`/workspace/shared/downloads/nasa_space_challenges.zip`; do not replace it with
a GitHub source tarball or a re-created ZIP. Hash the complete original file and
compare exactly with the expected SHA-256 above. On mismatch stop and report.
Only after success, inventory every member and compare against PR #11 by hash.
Create a separate source extraction directory; never execute contributed
binaries/build output. Read all contributed source, profiles, calculation methods,
tests, metadata and cited documents before adopting any code/data. Keep the
original archive and extracted originals immutable; implement repairs separately.
