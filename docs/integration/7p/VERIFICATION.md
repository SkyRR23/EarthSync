# Local verification — 14 November 2026

All listed suites actually ran. Logs and one full actual native Rust response
are in [evidence/](evidence/); machine-readable outcomes are in
[verification-summary.json](verification-summary.json).

| Check | Result |
| --- | --- |
| Deterministic offline tests | 55 passed, 0 failed, 0 skipped |
| Mechanical scientific safeguards | 14 passed, 0 failed, 0 skipped; no independent agronomist review |
| Native v0.3 integration | 5 tests passed, including all 10 request fixtures |
| Opt-in live source checks | 4 passed, 0 failed, 0 skipped: ECOCROP sheet, official license metadata, Myanmar calendar, CMR collection metadata |
| Existing v1 catalog tests | 39 passed; existing catalog check passed |
| Existing unchanged Rust engine suite | 118 passed, 0 failed, 0 ignored |
| Generated-data reproducibility | All 16 artifacts reproduced byte-for-byte; integrity check passed |
| Python Ruff lint / format | Passed |
| Protected-file checks | Original v1 catalog, engine types/assessment, v0.3 contract and 7J handoff hashes match the recorded base |
| Database indexing | Not applicable: no database introduced |
| SoilGrids numerical probe | **Unavailable/rejected**, not a passed numerical integration; explicit nodata absent |

The native fixtures prove that declared chronological gaps, overlaps and reversed
order reach the unchanged engine correctly. They preserve input sequence and
explicit fallow history. Catalog findings remain insufficient, candidates remain
empty and whole software-test summaries remain insufficient. These results do
not validate the synthetic dates, point, crop calendars or agronomic advice.

Reproduce from the repository root after installing v2's pinned requirements:

```sh
python data/crop-knowledge/v2/tools/build.py --check
python data/crop-knowledge/v2/tools/knowledge.py check
python -m ruff check data/crop-knowledge/v2/tools data/crop-knowledge/v2/tests
python -m ruff format --check data/crop-knowledge/v2/tools data/crop-knowledge/v2/tests
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_offline.py -v
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_scientific.py -v
cargo build --locked --manifest-path engine/Cargo.toml --example v03_demo
cargo test --offline --locked --manifest-path engine/Cargo.toml
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_rust_contract.py -v
EARTHSYNC_LIVE=1 python -m unittest discover -s data/crop-knowledge/v2/tests -p test_live.py -v
git diff --check
```

The local environment used Python 3.12.14 and the existing workspace Rust 1.99
toolchain. Offline native compilation requires locked dependencies cached first;
the executed Rust binary has no Python/network/model runtime dependency. The
standalone SoilGrids diagnostic used the existing 7I reader/transport and the
corresponding raster stack; its error was preserved without changing that code.

New remote CI is configured separately in `crop-evidence-v2.yml`; the local
results above do not claim remote workflow success. Live tests are excluded
from offline CI and require explicit opt-in. A known blocked/unsupported provider
is not a skipped passing test. GAEZ numerical extraction, satellite pixel access,
field observation, regional agronomy, browser/UI integration and deployment were
not tested or claimed by this data-only increment.
