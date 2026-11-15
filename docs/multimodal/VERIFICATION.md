# Verification receipts

All local results are from Linux on 2026-11-15. Source base is PR #34
`64ee5c625cbeb8ecf66d7ef2e4377f9a28c10448`. See the final draft PR for exact final
commit and remote CI status; inherited PR receipts are not counted as this patch's tests.

Initial broad regression after integration: **567 passed, 7 skipped** (existing live
opt-ins and environment-specific skips), using actual compiled native engine and
base-exported compatibility interfaces. Focused multimodal/research run:
**101 passed**, overlapping that broad suite. Subsequent final receipts are listed
in `evidence/` and the draft PR; do not add overlapping counts.

Original 7V suite: **32 passed**. Source integrity: 49 v2 artifacts, 11 review
artifacts, 35 scientific input pins; **60 blocked candidates, zero executable rules**.
Rust suite passed; see `evidence/rust-summary.txt` for exact test-group totals.

Coverage includes legacy API contracts, ownership/scopes, image sanitization,
consent before provider pixels, genuine adapter image request shape over mocked
HTTP, no redirects/retries, timeout/rate/auth/access/network failures, bad/oversized/
truncated output, printed-instruction/model-field injection, wrong crop/region,
unclear images, no-evidence fallback, exact citations and blocked-rule preservation.
Local backup/restore regression retains local OCR, AI transcription and corrected
values separately. Existing actual Tesseract synthetic-report test runs when installed.

**No live vision provider call**, by explicit user selection. **No real agricultural
accuracy, report authenticity or labeled-image accuracy** is claimed. No hosted
teammate compatibility or interactive Windows destination acceptance is claimed.
Initial local Flutter setup failed with network policy 403; that is not a passing
Flutter test. Remote CI and any later browser receipts must be reported separately.

Reproduce from repository root with a task-owned venv and existing locks:

```sh
export PYTHONPATH="$PWD/server"
python -m pytest -q server/tests/research
python server/platform-v1/tools/prepare_compat.py /tmp/earthsync-mm-compat --revision 660b479c3ffb714cd1d489e1241c026ceae6ed67
cargo build --locked --manifest-path engine/Cargo.toml --example v03_demo --example web_engine
EARTHSYNC_COMPAT_ROOT=/tmp/earthsync-mm-compat EARTHSYNC_TEST_V03="$PWD/engine/target/debug/examples/v03_demo" python -m pytest -q server/tests ops/staging/tests
cargo test --locked --manifest-path engine/Cargo.toml
python scripts/verify_7x_integrity.py
python data/crop-rule-candidates/v1/tools/package.py --check
python -m unittest discover -s data/crop-rule-candidates/v1/tests -v
cargo build --release --locked --manifest-path app/rust/Cargo.toml
cd app
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test test_support example
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run --dart-define=PLATFORM_URL=http://127.0.0.1:8021
```

Start both local services via `scripts/run_final_local.py`, generate the existing
labeled synthetic report and use `scripts/browser_crop_intelligence.py` for actual
Chromium, no mocked HTTP. Private browser outputs must be outside Git. Windows
commands and required human acceptance are described in USER_ACTIONS_REQUIRED.md.

Actual loopback HTTP smoke passed: scoped retrieval with seven citations, private
PNG upload, new-contract vision-unavailable response, actual local Tesseract on a
labeled synthetic report, explicit 6.4 → 6.6 correction with original retained,
401 unauthenticated image access and deletion. No external model was called.
See `evidence/loopback-http.json`.

The first remote Flutter attempt stopped at its formatting gate; the exact Dart
formatter patch was retrieved and applied. Both Windows/Linux research contract
jobs passed. No skipped analyzer or widget step is counted as a pass.
