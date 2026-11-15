# Reproducing the immutable-candidate validation

Subject: `660b479c3ffb714cd1d489e1241c026ceae6ed67`. Source workstreams: 7X `665cbecce3575724ded5145863a6823b44773a69`, 7G `27584a6e506ecda362be516b113b850c6ac98259`, integrated PR [#29](https://github.com/SkyRR23/EarthSync/pull/29). Main is not this candidate. The validation PR contains only `tests/global_validation` and `docs/validation`; check its exact head before reproduction.

## Environment

Tested on Linux x86-64, Python 3.12.14, native Rust v0.3, Flutter 3.44/Dart 3.12, Chromium and Playwright 1.56. Source remains immutable during measurements. Follow the candidate's [runbook](../release/RUNBOOK.md), [Windows acceptance](../release/WINDOWS_ACCEPTANCE.md) and [artifact instructions](../release/ARTIFACTS.md) for actual startup. Global measurements here are Linux measurements, not interactive Windows acceptance.

Create an isolated worktree at the validation PR head, not in an active development worktree. Install the pinned `server/requirements.lock` in a virtual environment. Browser reproduction additionally needs Playwright 1.56 and an installed Chromium executable. Build the native `v03_demo` example from this candidate, or use its verified full-stack artifact. The measured binary's SHA-256 was `00d9175eb0bf6bb3c426a635d89d6a1c41fe0bfcdef1d299e40bc0afac5cae37`; rebuilding with another compiler can produce different bytes, so record the new binary hash. Do not claim byte-identical binary reproduction without a match.

Set task-specific paths, for example (Bash):

```bash
VALIDATION_PRIVATE=/absolute/private/new-run
VALIDATION_ENGINE=/absolute/artifact/source/engine/target/debug/examples/v03_demo
VALIDATION_PYTHON=/absolute/venv/bin/python
mkdir -m 700 "$VALIDATION_PRIVATE"
export PYTHONDONTWRITEBYTECODE=1
export EARTHSYNC_TEST_V03="$VALIDATION_ENGINE"
"$VALIDATION_PYTHON" -B -m pytest -q tests/global_validation/test_validation.py
```

Never point at a real farmer database. Never reuse the previous run directory as a fresh observation. `run.py` checks production-file equality against the pinned baseline and the frozen site-manifest hash before network access.

## Bounded live production-path run

```bash
VALIDATION_ENGINE_SHA=$(sha256sum "$VALIDATION_ENGINE" | cut -d ' ' -f 1)
"$VALIDATION_PYTHON" -B tests/global_validation/run.py \
  --live --private "$VALIDATION_PRIVATE/runtime" \
  --output "$VALIDATION_PRIVATE/new-results" \
  --engine "$VALIDATION_ENGINE" --engine-sha "$VALIDATION_ENGINE_SHA"
```

`--live` is explicit opt-in. The frozen protocol limits requests to 230, per-source body size to 4 MB and nominal concurrency to two; cache admission serializes transport calls. Identical cached requests retain original retrieval timestamps/hashes and are not new observations. Production provider errors remain unavailable; no fake fallback data are emitted. The output directory must contain `evidence/` before the run if created separately (`mkdir -p "$VALIDATION_PRIVATE/new-results/evidence"`). The existing `scripts/verify_7x_integrity.py` is read-only and is also called by `export_summaries.py`; no scientific hashes are regenerated. Use a fresh copy of the validation worktree when running supplemental scripts, because their reviewable summary paths are intentionally fixed under `docs/validation`.

## Reference and supplemental measurements

After preserving original published summaries, in a disposable validation worktree:

```bash
"$VALIDATION_PYTHON" -B tests/global_validation/reference_probe.py --private "$VALIDATION_PRIVATE"
"$VALIDATION_PYTHON" -B tests/global_validation/weather_agreement.py --private "$VALIDATION_PRIVATE"
"$VALIDATION_PYTHON" -B tests/global_validation/probes.py --private "$VALIDATION_PRIVATE"
"$VALIDATION_PYTHON" -B tests/global_validation/performance.py --engine "$VALIDATION_ENGINE"
"$VALIDATION_PYTHON" -B tests/global_validation/export_summaries.py --private "$VALIDATION_PRIVATE"
```

`weather_agreement.py` reads `runtime/<site>/<period>.json` and official station bodies under `references/`. For a fresh run, first stage the new main-run output into the disposable worktree's `docs/validation` before supplemental scripts/report rendering. These scripts never overwrite the release's original evidence outside this validation folder. No raw NOAA annual files, source PDFs, TIFF bodies, test databases or local browser state should be committed. Format checking rejects HTTP-200 HTML before measurement. Missing field observations remain missing. Read source licensing before retrieving or sharing data.

For the local regression subset:

```bash
PYTHONPATH=server "$VALIDATION_PYTHON" -B -m pytest -q \
  server/tests/platform_v1/test_geospatial_7g.py \
  server/tests/platform_v1/test_soil_webdav.py \
  server/tests/platform_v1/test_forecast_7g.py \
  server/tests/platform_v1/test_contracts_providers.py \
  server/tests/platform_v1/test_comparisons.py \
  server/tests/platform_v1/test_comparison_assistant.py \
  server/tests/platform_v1/test_journal.py \
  server/tests/platform_v1/test_journal_projection.py \
  server/tests/platform_v1/test_farmer_timeline.py \
  tests/global_validation/test_validation.py
```

These include SYNTHETIC and MOCKED outage/ownership/geometry cases; read per-test fixture provenance. They do not become live-provider verification.

## Browser reproduction

Use separate loopback services, not the existing private release store. The measured test build used `PLATFORM_URL=http://127.0.0.1:8061` and Web port `8097`; `browser_sites.py` deliberately fixes these test-only addresses. Start the actual platform factory with `EARTHSYNC_PLATFORM_LOCAL=1`, a new `EARTHSYNC_PLATFORM_DIR=$VALIDATION_PRIVATE/ui-platform`, allowed origin `http://127.0.0.1:8097`, and the candidate's pinned engine/catalog environment. Compile actual Flutter Web with this URL, run `python scripts/finalize_offline.py app/build/web` as documented by the candidate build instructions, and start `earthsync.web_demo:app` on 127.0.0.1:8097. Keep TLS checks enabled for external sources. This is a local single-user deployment, never a public multi-user service.

```bash
"$VALIDATION_PYTHON" -B tests/global_validation/browser_sites.py seed \
  --private "$VALIDATION_PRIVATE" --engine "$VALIDATION_ENGINE"
"$VALIDATION_PYTHON" -B tests/global_validation/browser_sites.py browser \
  --private "$VALIDATION_PRIVATE"
```

Seeding explicitly creates synthetic reported fields/history/three-strategy groups in a disposable store using production classes. Actual farm selection and saved comparison reopening use compiled Flutter in a persistent Chromium profile. This does not claim manual creation at all 12 locations. Private screenshots and diagnostics can contain generated IDs; they are excluded from Git. `EARTHSYNC_VALIDATION_SITE` optionally restricts a diagnostic rerun to one public site; do not report that as a 12-site result.

Finally render tables with `report.py` only after checking actual machine-readable results, then inspect all generated claims and links. `report.py` does not change scientific eligibility. No script merges main or deploys publicly.
