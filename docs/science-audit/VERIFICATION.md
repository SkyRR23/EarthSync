# Verification record

All checks below were run locally for this audit. They establish software
behavior and source-contract handling, not independent agronomic validity.

| Check | Result |
| --- | --- |
| Unpatched 7H + new NASA regressions | 15 failed, 1 passed: failures expose J01–J04, not pre-existing Jan/Feb aggregation drift |
| Unpatched v0.3 + new Rust regressions | 2 failed, 5 passed: regional predecessor/fallow wrongly supported |
| Patched Rust full suite | 118 passed, no ignored tests; all 111 pre-existing tests retained plus 7 new tests |
| Patched final 7H backend | 288 passed, no skips; includes actual compiled Rust HTTP boundary and retained real NASA capture replay |
| Global catalog + inventory tool | 45 passed plus 32 subtests: existing 39 catalog tests and six new ZIP tests |
| Exact 7I source with exact compatibility pins and original compiled v0.3 | 83 passed, 3 opt-in live-provider tests skipped; no compatibility-engine skips |
| 7I plus isolated J06 handoff patch | 85 passed, 3 opt-in live-provider tests skipped; unpatched precision regression fails with SPATIAL_MISMATCH |
| Combined scientific CI command | 63 passed plus 32 subtests; source regressions, catalog and ZIP inventory tool |
| Live POWER high-precision query | Two-day original response preserved and hashed; patched full-February normalization succeeded with explicit query and rounded returned point |
| Rust formatting / all-target Clippy | Passed |
| Changed Python/tool Ruff lint | Passed |
| New archive checksum/inventory/Myanmar sources | BLOCKED on part 03; six wrapper/chunk hash pairs match manifest. Full original hash remains unverified. |

The first broader backend attempt lacked Pillow and the new worktree's engine
binary. Those setup failures were resolved with a separate pinned Python
environment and a source build. Final 7H used its own `server/requirements.lock`;
7I used its separate `server/platform-v1/requirements.lock` in another temporary
environment. Neither existing workspace environment nor another branch was edited.

7I's test count above is the independently observed count for the named directory,
not the larger aggregate test count reported in its PR. The three skipped tests
are NASA/soil/HLS opt-in network acceptance tests. No new live satellite, soil,
forecast or NASA correctness claim follows from their omission or capture replay.
The separate actual NASA precision probe verifies current provider serialization
and adapter behavior; it does not establish farm accuracy or crop applicability.

## Commands

From repository root, with the project Rust toolchain and pinned Python environment:

```sh
cargo test --locked --offline --manifest-path engine/Cargo.toml
cargo fmt --check --manifest-path engine/Cargo.toml
cargo clippy --all-targets --locked --offline --manifest-path engine/Cargo.toml -- -D warnings
cargo build --locked --offline --manifest-path engine/Cargo.toml --example web_engine
PYTHONPATH=server python -m pytest -q server/tests
python -m pytest -q data/crop-knowledge/v1/tests tools/science_audit
ruff check server/earthsync/source_validation.py server/earthsync/power.py server/tests/test_science_audit.py server/tests/test_backend.py tools/science_audit
git diff --check
```

The 7I source was exported from `b578a6df` to `/tmp/earthsync-7i`, and its
reviewed `prepare_compat.py` exported exact PR #14/#15/#16/#18 pins to
`/tmp/earthsync-audit-compat`. Its source-built original `v03_demo` was supplied
through `EARTHSYNC_TEST_V03`, with `EARTHSYNC_COMPAT_ROOT` set to those exports.
No generated binary from either contributed archive was used.

To repeat PR #11 inventory (obtain its original ZIP from its exact Git commit):

```sh
python tools/science_audit/inventory_zip.py field-shift-data-pack.zip --compare archive_inventory.json
```

The original PR #11 SHA-256 was checked independently; member content hashes match
its original inventory. The new archive comparison remains pending. Do not
publish a completed 7J acceptance claim based on this partial inventory.
