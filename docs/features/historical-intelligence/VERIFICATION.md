# Verification and exact scope

Production implementation pin: `004381b916345edbc84b3ee539e0b4dd17ef6dca`. It is based exactly
on PR #29 source `660b479c3ffb714cd1d489e1241c026ceae6ed67`. Subsequent handoff
commits add tests, browser drivers, documentation and reviewed screenshots; their
production trees must remain identical to this implementation pin. PR #33 records
the final handoff SHA and latest exact-commit package run.

## Automated regression

| Check | Observed result |
|---|---|
| Full local Python/backend/operations | **480 passed, 7 explicit skips** |
| Full Flutter/native bridge suite | **137 passed, 3 explicit live skips** |
| Flutter analyzer / production Web | Clean / compiled with Flutter 3.44.0, Dart 3.12.0 |
| Existing Rust suite | Passed; engine tree unchanged from base |
| Integrity checks | 49 catalog files, 11 review files and 35 original scientific input pins retained; **60 blocked candidates, 0 executable rules** |
| Exact production-commit CI | All 15 relevant checks passed on `004381b`: Windows/Linux Python 3.12/3.13, Docker, Rust, scientific contracts, assistant, Flutter and Windows/full-stack packaging |

The package workflow for this code is [run 43676451986](https://github.com/SkyRR23/EarthSync/actions/runs/43676451986).
The backend/Docker workflow is [run 43676452043](https://github.com/SkyRR23/EarthSync/actions/runs/43676452043).
The latest final-handoff package run and downloadable Windows/Linux artifacts are
linked in [draft PR #33](https://github.com/SkyRR23/EarthSync/pull/33). A Windows CI
build/startup pass is distinct from the user's interactive Windows acceptance.

## Real source cohort

The software-test region is Myanmar. Farm polygons, histories, assumptions and
crop choices are **synthetic software-test fixtures**, not farmer observations or
agricultural ground truth. Environmental inputs are real NASA POWER daily
MERRA2/SYN1DEG and calculated native Rust reference ET0.

* Eleven full annual windows: **2015-01-01 through 2025-12-31**, fetched separately.
* **88 NASA input records + 11 derived Rust evidence records**.
* Rainfall and original T2M mean temperature: **4,018 accepted days each**.
* Reference ET0: **3,959 accepted days; 59 withheld by existing domain checks**.
* 2024: 1,100.48 mm rainfall, 366/366 days; ET0 353/366 accepted days.
* 2025: 984.25 mm rainfall, 365/365 days; ET0 359/365 accepted days.
* Annual accepted-day ET0 subtotals never stand for complete-period totals. All
  eleven annual ET0 totals remain incomplete, so their complete-season baseline
  sample count is zero. No silently imputed climate baseline is claimed.

See [annual values](evidence/nasa-periods.csv), [source classifications and hash
receipt](evidence/source-summary.json), and [source/rights report](DATA_SOURCES.md).
No station/field accuracy score or crop-damage threshold was established.

GIBS capabilities were validated against the real layer time dimension. Actual
browser tile HTTP 200 responses confirmed different requested image dates, with
normal TLS. Exact acquisition time stays unknown. The original accepted SoilGrids
RUN05 WebDAV extract was shown with raw values, scale, native 250 m support and
0–5 cm depth; it stays fixed across replay dates.

Numerical NDVI remains unavailable. A successful HLS HEAD did not establish pixel
access: the bounded pixel GET returned 401 HTML, and MODIS discovery timed out.
No red/NIR, QA or polygon NDVI result is claimed.

## Actual compiled-browser acceptance

`browser_historical.py` exercised the compiled app against the real local API,
SQLite, NASA archives and native Rust. Its core run passed **17 grouped stages**:
confirmed saved farm; 2024 source/ET0; playback; dated GIBS/static soil; two-date
image comparison; baseline/A/B; changed planting-date outputs; water assumptions
with withheld irrigation quantities; 2024/2025 comparison; eleven-year context;
explicit device save; cold offline reload; as-of filtering; reproducible duplicate;
import/new reassessments; reported/unknown chronology; mobile rendering and no
unhandled page errors. Some related checks share a stage; this is not a claim
that all numbered prompt steps were separate clicks.

A separate final saved-state run on the final compiled production sources passed
reopen/duplicate/as-of/reproducibility, existing-comparison import, reported
history, mobile rendering, and **injected current-provider failure with accepted
historical online fallback**. It had zero unhandled page or Flutter render errors.
The failure was a browser-only test injection; real NASA responses were retained.

`browser_historical_empty.py` created another explicitly synthetic linked revision
with no evidence. Both online no-evidence and cold offline no-cache states showed
unavailable, with no fabricated values and no unhandled page errors.

The isolated API was restarted after recording hashes of every saved farm,
evidence, decision, history, journal, comparison, archive and simulation document.
All document hashes were unchanged after restart. A fresh SQLite backup/restore
passed integrity and saved-result checks. The final HTTP assistant context
answered the actual 2024/2025 rainfall question with matching dates and citations.

The browser runs are separate, and their stage counts are not summed into a
single uninterrupted run. The [allowlisted receipt](evidence/acceptance-summary.json)
records their scope. Raw runtime state, identifiers, coordinates, source payloads,
private databases and browser profiles remain outside Git.

## Failures retained rather than hidden

* Initial Flutter SDK access was denied by environment network policy; the user
  added the needed hosts. No policy bypass was used.
* GIBS capabilities were 5,842,320 bytes, exceeding the generic 4 MB transport cap.
  A dedicated bounded 8 MB metadata limit fixed retrieval; data products retain
  their 4 MB limit.
* An incorrectly encoded test SharedPreferences fixture initially hit the farm
  confirmation gate. Correct fixture encoding opened the actual saved farm.
* Early browser drivers scrolled over the map, hit overlapping Flutter semantic
  nodes, or asserted before asynchronous computations finished. Those failed runs
  are not acceptance passes. Persistent workspace sections, literal accessible
  selectors, settled viewport scrolling and actual job-completion checks resolved
  the test path.
* Chromium could not initialize its existing certificate database in the restricted
  runner. The user approved temporary CA trust, but fingerprint inspection showed
  that CA was already trusted under its environment-provided name. No additional
  entry was created. The browser was run with access to its existing database;
  normal TLS verified the actual GIBS tiles. No `ignore_https_errors` or global
  certificate-error flag was used.

## Remaining integration gates

Keep PR #33 draft. Do not overwrite PR #29/#31, deploy or merge main automatically.
The independent Windows-tested release is unchanged. User interactive Windows
acceptance, native-language agricultural/accessibility review and explicit final
release approval remain separate gates. No numerical NDVI, agricultural prediction,
real-time readiness or scientific suitability approval is claimed.
