# 7V verification receipts

Validated code/data checkpoint: **`e537f6b8cf23fa26bcb59fd3c78526bbc6995576`**.
Base: `940a8aad62da8b188cdd3af4d200f353d907997a` (7P #25).
The delivery commit adds this verification record, raw logs and a documentation
clarification; the validated package, workflow, engine and 7P files are unchanged.
The draft PR description records the exact delivery SHA, avoiding a self-referential
commit hash inside its own content.

All 11 receipt commands passed. **224 tests passed, zero failures or skips.**
They establish software contracts, arithmetic, retained source integrity and
bounded source comparisons. They do not establish agronomic safety or field
applicability. No crop rule or eligibility flag was approved.

| Check | Observed result | Receipt |
| --- | --- | --- |
| 7V strict candidate, published method and native arithmetic suite | 32 passed; includes three actual unchanged Rust numerical checks | [7v-tests.log](evidence/7v-tests.log) |
| Existing 7P offline catalog suite | 55 passed | [7p-offline.log](evidence/7p-offline.log) |
| Existing 7P scientific safeguard suite | 14 passed | [7p-scientific.log](evidence/7p-scientific.log) |
| Existing 7P native v0.3 contract suite | 5 passed, exercising ten fixture requests | [7p-native.log](evidence/7p-native.log) |
| Existing Rust engine suite | 118 passed | [rust-engine.log](evidence/rust-engine.log) |
| 7V read-only deterministic rebuild and input/graph integrity | Passed | [package-check.log](evidence/package-check.log) |
| Existing 7P deterministic rebuild | Passed | [upstream-build-check.log](evidence/upstream-build-check.log) |
| Ruff lint and format | Passed | [ruff-check.log](evidence/ruff-check.log), [ruff-format.log](evidence/ruff-format.log) |
| Locked offline native source build | Passed; Rust 1.99.0 | [native-build.log](evidence/native-build.log) |
| Patch whitespace | Passed | [diff-check.log](evidence/diff-check.log) |

[Machine receipt](evidence/verification-summary.json) records the exact tested
commit, argv, UTC start/completion, exit code, duration, count, raw-log hash,
validated-file hashes, Python/Rust versions and locally built binary hash.
No generated binary or bytecode is committed. Receipt paths reflect this isolated
environment; the commands below are portable equivalents.

Seven official-source responses were fetched during this independent review.
[Source receipts](../../../data/crop-rule-candidates/v1/source-receipts.json)
preserve exact body hashes and retrieval times; full texts/API bodies are not
redistributed. The [source comparison](evidence/source-comparison.json) records
55 matching selected calendar sessions and 28 populated ECOCROP claims.
The ecological match uses retained original FAO sheets and the reviewed 7P parser,
plus independent manual inspection. It is not an independent second parser.
These are source review receipts, not seven additional automated field tests.

The FAO-56 Example 28 day-40 source value is rounded to 0.77; exact interpolation
is 0.774. Tests respect that precision. The 100-day 358.50 mm and 381.00 mm values
use hypothetical ETo = 5 mm/day; neither is a published priority-crop requirement.
The sesame 110-versus-100-day disagreement remains an expected blocked source
condition. Passing tests assert its preservation rather than repairing the source.

Run from the repository root with Python 3.12+:

```sh
python -m pip install -r data/crop-knowledge/v2/requirements.txt
python data/crop-rule-candidates/v1/tools/package.py --check
python data/crop-knowledge/v2/tools/build.py --check
python -m ruff check data/crop-rule-candidates/v1
python -m ruff format --check data/crop-rule-candidates/v1
cargo build --locked --manifest-path engine/Cargo.toml --example v03_demo
python -m unittest discover -s data/crop-rule-candidates/v1/tests -v
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_offline.py -v
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_scientific.py -v
python -m unittest discover -s data/crop-knowledge/v2/tests -p test_rust_contract.py -v
cargo test --locked --offline --manifest-path engine/Cargo.toml
git diff --check
```

Local dependency installation precedes the offline checks. BeautifulSoup was
used only for manual inspection of temporary downloaded HTML and is not a package
or test dependency. The committed tools use the existing 7P dependency pins.
Network source availability, original full-text scientific accuracy, new soil/
satellite/forecast acceptance and agronomist/field validation are not tested here.
No Rust algorithm, FastAPI/Flutter file, 7J artifact or existing profile changed.
The added CI workflow runs candidate/native and inherited scientific boundaries;
this local receipt does not claim a remote CI result.
