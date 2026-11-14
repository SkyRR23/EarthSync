# Verification record

These checks establish software behavior, integrity and bounded source review,
not independent field accuracy or farming advice.

| Check | Observed result |
| --- | --- |
| Current 7N source snapshot | PR #24 at `530c1e1d`: all six modern corrections present; four scoped files match reviewed code and 7I adds coordinate-domain checks. Source-only scope |
| Original reconstructed archive | 55,057,221 bytes; complete expected SHA-256 matched before content inspection |
| Full inventory / unchanged originals | 743 members, 600 files hashed/CRC checked; 113 extracted non-build files rehashed unchanged; 487 build files rejected |
| PR #11 comparison | 60 byte-identical files; README/API notes differ; new source/raw/crop records inspected separately |
| Unpatched 7H new NASA cases | Initial 15 failed, one missingness control passed; later coordinate precision cases added |
| Patched modern Rust suite | 118 passed: all 111 original tests plus seven new scientific tests |
| Patched final 7H backend | 288 passed, no skips; actual source-built Rust HTTP boundary and captured NASA replay included |
| Scientific source/catalog/tool command | 83 passed plus 32 subtests: 18 NASA cases, 39 catalog tests, 26 research/inventory tests |
| Exact unmodified 7I + original pinned engine | 83 passed, three opt-in live-provider skips; no compatibility-engine skips |
| 7I plus isolated J06 handoff patch | 85 passed, same three skips; new precision case fails on unpatched 7I |
| Contributed engine clean source rebuild | 13 original tests passed offline |
| Contributed engine desired-property regressions | 12 deliberately failing scientific checks; full failures recorded, not included as modern passing tests |
| Live NASA precision check | Original body preserved/hashed; full leap-February normalization at precise point succeeded |
| Live NASA historical precipitation repeat | All 390 Hlegu 1991–2020 stored monthly/annual values matched current one-parameter response |
| Crop primary-source review | 11 directly readable ECOCROP sheets; sunflower direct error but indexed original-source reference matched; no executable rule accepted |
| Rust formatting / all-target Clippy | Passed for modern engine |
| Changed Python/tool Ruff lint/format and patch integrity | Passed |

The original archive/helper checksum chain is recorded in
`evidence/reassembly-verified.json`. Earlier transfer errors in `split-transfer.json`
are superseded. All provided helper sources were read before authorized execution.
Only freshly compiled historical executables were run, never the supplied builds.

The first broader backend attempt lacked Pillow and the new worktree binary.
Setup was resolved using separate pinned environments and source compilation:
7H `server/requirements.lock`, 7I `server/platform-v1/requirements.lock`.
Neither another worktree nor the user's existing environment was modified.

The 7I count is the independently observed named-directory count, not its PR's
larger aggregate. The skipped tests are NASA/soil/HLS opt-in network acceptance.
No live satellite, soil, forecast or crop correctness follows from those skips.
The separate NASA network checks establish serialization and matching provider
numbers only; original contributed retrieval timestamps remain unknown.

## Modern repeatable commands

```sh
cargo test --locked --offline --manifest-path engine/Cargo.toml
cargo fmt --check --manifest-path engine/Cargo.toml
cargo clippy --all-targets --locked --offline --manifest-path engine/Cargo.toml -- -D warnings
cargo build --locked --offline --manifest-path engine/Cargo.toml --example web_engine
PYTHONPATH=server python -m pytest -q server/tests
PYTHONPATH=server python -m pytest -q -c server/pyproject.toml server/tests/test_science_audit.py data/crop-knowledge/v1/tests tools/science_audit
ruff check server/earthsync/source_validation.py server/earthsync/power.py server/tests/test_science_audit.py server/tests/test_backend.py tools/science_audit
ruff format --check server/earthsync/source_validation.py server/earthsync/power.py server/tests/test_science_audit.py tools/science_audit
git diff --check
```

7I source was exported from `b578a6df` to `/tmp/earthsync-7i`; its reviewed
`prepare_compat.py` exported exact PR #14/#15/#16/#18 pins to
`/tmp/earthsync-audit-compat`. The source-built original `v03_demo` was supplied
via `EARTHSYNC_TEST_V03`, with `EARTHSYNC_COMPAT_ROOT` pointing at those exports.
A second exact export applied the standalone coordinate patch and passed 85 tests.

Historical reproductions and safe source-build instructions are in
[ARCHIVE_FINDINGS](ARCHIVE_FINDINGS.md). The provided old tests pass despite
scientific defects; they are not agronomic validation. The negative historical
suite is intentionally separate from production CI. New source/catalog/quarantine
regressions run in the dedicated scientific workflow.

## Archive data repeatability

```sh
python tools/science_audit/audit_contribution.py ORIGINAL.zip --compare PR11_INVENTORY.json --output REVIEW_OUTPUT
```

This verifies the complete pinned checksum before reading content, then creates
full inventory, source review and reference-only outputs. No archive code is
executed. Source review availability is an explicit recorded desk-review decision,
not automatically inferred from URL strings or software output.

Remaining uncertainty: independent agronomist/field acceptance, trusted forecast
run identity, satellite/soil QA and local representativeness, original fetch
receipts, full unavailable FAO handbook review, crop-stage ET0/Kc/water balance,
and validated regional/cultivar management evidence. No recommendation flag was
promoted and no missing evidence was represented as measured.

CI at code/artifact checkpoint `893553d` passed all eight reported checks: Rust,
scientific contracts, Flutter bridge, and Linux/Windows Python 3.12/3.13. The
subsequent 7N snapshot note changes documentation only.
