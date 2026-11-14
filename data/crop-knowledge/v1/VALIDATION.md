# Validation record

Host validation: 14 November 2026, Python 3.12.14, jsonschema 4.26.0,
Ruff 0.14.5. Baseline: `origin/feat/web-demo` at
`e0cdaaf875efb376e3081a66826b4b5e21601c67`. Isolated branch:
`data/global-crop-knowledge`; worktree: `/workspace/EarthSync-7g`.
No AGENTS.md was present in the inspected repository/workspace.

From `/workspace/EarthSync-7g`:

```sh
python data/crop-knowledge/v1/tools/catalog.py build
python data/crop-knowledge/v1/tools/catalog.py check
python -m unittest discover -s data/crop-knowledge/v1/tests -v
/workspace/.earthsync-python/bin/ruff check data/crop-knowledge/v1/tools data/crop-knowledge/v1/tests
/workspace/.earthsync-python/bin/ruff format --check data/crop-knowledge/v1/tools data/crop-knowledge/v1/tests
git diff --check
```

The `build` command generated eight profiles, 13 sources, four pilot cases and
the audit. The final offline test run passed 39 tests. Ruff lint and formatting,
deterministic artifact/checksum validation and patch whitespace checks passed.
Actual CLI lookups exercised an Iowa crop, an uncovered Myanmar scope and fallow
with a null crop ID. The draft PR records independent CI outcomes.
For another machine, install `requirements.txt` in a venv and replace the
host-specific Ruff path with that venv's `python -m ruff`.

Coverage includes source and parameter linkage, unit identity, source date
precision, unknown/null preservation, synthetic/reference review separation,
regional/production-system isolation, calendar token and cross-year validity,
exact-scope lookup, separate fallow identity, deterministic artifact generation,
checksum audits and transport failure handling. Transport-success tests use
explicitly synthetic bytes. They do not claim a provider download succeeded.

Actual source access:

- Successful web research extraction of all 13 original institutional source
  pages/documents in a batch completed at `2026-11-14T09:19:18Z`.
- Direct source HTTP fetch via the implemented capture command returned zero
  available and 13 unavailable receipts, exit code 1. Every failure was proxy
  tunnel 403. Command:
  `python data/crop-knowledge/v1/tools/capture_sources.py --output /tmp/earthsync-7g-http-audit`.
  The original receipt bytes are retained in `evidence/http-retrieval-audit.json`.
  A rerun must choose a new output directory.

No Rust, Flutter or backend integration files were modified. Their test suites
are not substitutes for these data checks and were not rerun by this task.
No browser, Android, live environmental API, full provider-response download,
farm experiment, independent agronomist review or scientific field validation
was performed or claimed. 7E contract acknowledgment remains pending.
