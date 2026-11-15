# Verification and reproducibility

Base source: `660b479c3ffb714cd1d489e1241c026ceae6ed67` (PR #29).
Scientific review: `5ffe71e45f0f141d0e383cd437ab35c843960dc6` (PR #26).
New branch: `feat/earthsync-crop-intelligence-rag-v1`.
Tests below ran on the isolated Linux worktree, 2026-11-15. No release/historical/
realtime/Groq worktree was edited. A source commit identifies the final reviewed
artifact in Git; raw runtime state and temporary credentials stay outside Git.

| Check | Observed result |
|---|---|
| All existing Python/server/operations tests plus first 61 research tests | 527 passed, 7 skipped; actual native engine configured, base-exported compatibility interfaces |
| Final focused research contracts (including CLI/schema additions) | 63 passed; overlaps the broad suite, not an additional 63 independent checks |
| Existing Rust engine | 124 passed; unchanged algorithms |
| Full 7V original scientific review tests | 32 passed; zero approved rules |
| Source integrity | v1 exact hash; 49 v2 artifacts; 11 7V artifacts; 35 input pins; 60 blocked candidates |
| Flutter analyzer | Clean final recheck: no issues |
| Full Flutter, actual native bridge built | 135 passed, 3 live-provider skips |
| Flutter production Web | Final release build passed with the upload response fix |
| Actual Chromium | Cited crop retrieval → private synthetic report upload → actual local OCR → original-image correction editor; zero page errors, no mocked HTTP |
| Real local Tesseract | Labeled synthetic report read; pH 6.4, units, sample ID, depth/method retained pending confirmation |
| Local recovery | Research SQLite snapshot/restored credentials/photos; farmer SQLite/object backup restored corrected lab report; photo deletion cascaded reports |
| Actual research HTTP client | Authenticated source retrieval, synthetic PNG upload, unavailable vision response, authorized deletion passed on loopback |
| Teammate Firebase health | Public and supplied test host each returned 200, `upstream_checked:false`; test OpenAPI paths 404; local-origin CORS header absent |
| External AI/real agricultural image evaluation | Not performed; no provider configured or cloud photo transfer |
| Docker build / runtime smoke | Existing GitHub platform CI container job passed at implementation commit `90652b2b8d709679fa14db55d427e077f5dab83c`; extended smoke checks cited retrieval |
| Windows/Linux research CI | 62 passed, 1 optional local-Tesseract skip on each OS at implementation commit; no interactive Windows destination/ACL acceptance claimed |
| Exported container runtime closure | Fresh temporary copy of runtime modules/catalog and the four allowlisted 7V JSON files imported successfully and returned hash-checked cited evidence |

Optional/live provider and environment-specific skips are explicit; local offline
tests do not establish NASA/soil live provider health. Existing dependency
deprecation warnings are not agricultural findings. A synthetic fixture is not
measured soil ground truth. Provider mock tests are labeled in `test_soil.py`.

The first browser attempt exposed the upload transport's request/response MIME
confusion. The fix decodes JSON metadata using the actual response Content-Type
while retaining the existing fallback for headerless transports. Its regression
is included in the 135-test Flutter result. Earlier failed harness attempts are
not counted as browser acceptance; the final smoke receipt is reported separately.
The first remote full-Flutter job failed only its format gate on two new files;
the subsequent formatting-only delivery corrects this and adds the same gate to
the new workflow. The locally browser-tested implementation is `90652b2b8d709679fa14db55d427e077f5dab83c`;
later whitespace/CI/documentation changes do not alter runtime behavior. Inspect
the final-head GitHub checks separately; earlier failure is not represented as a pass.

## Commands

Use Python 3.12+ and the existing locks; keep tool caches/private state outside Git.

```sh
python -m pip install -r server/requirements.lock
export PYTHONPATH="$PWD/server"
python -m pytest -q server/tests/research
python server/platform-v1/tools/prepare_compat.py /tmp/earthsync-compat --revision 660b479c3ffb714cd1d489e1241c026ceae6ed67
cargo build --locked --manifest-path engine/Cargo.toml --example v03_demo --example web_engine
EARTHSYNC_COMPAT_ROOT=/tmp/earthsync-compat \
EARTHSYNC_TEST_V03="$PWD/engine/target/debug/examples/v03_demo" \
python -m pytest -q server/tests ops/staging/tests
cargo test --locked --manifest-path engine/Cargo.toml
python scripts/verify_7x_integrity.py
python data/crop-rule-candidates/v1/tools/package.py --check
python -m unittest discover -s data/crop-rule-candidates/v1/tests -v
cargo build --locked --release --manifest-path app/rust/Cargo.toml
cd app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run --dart-define=PLATFORM_URL=http://127.0.0.1:8021
cd ..
python scripts/run_final_local.py --directory /tmp/earthsync-crop-platform
# In another terminal, with Playwright and Chromium installed:
python server/examples/make_synthetic_lab_report.py /tmp/synthetic-soil-report.png
python scripts/browser_crop_intelligence.py --lab-image /tmp/synthetic-soil-report.png --output /tmp/earthsync-browser-receipts
```

For sandboxed Flutter tools use `PUB_CACHE`, `XDG_CONFIG_HOME` and
`ANALYZER_STATE_LOCATION_OVERRIDE` in task-owned temporary directories; keep HOME
unchanged. The pinned release archive URL was unavailable; SDK tag `3.44.0` was
cloned and reported Dart 3.12.0. Initial missing native/cache setup failures were
resolved before the reported passing suites.

## Security/science coverage

Tests reject missing/invalid/revoked/expired credentials, wrong scope, cross-tenant,
cross-user, same-owner-without-grant and wrong-farm image/report access. They cover
host/origin/HTTPS enforcement, raw/chunked upload size, corrupt/spoofed images,
JPEG metadata stripping and pixel limits, persistent rate limits, no secret in
audit/database/API responses, private secret-file creation, schema drift, report
confirmation, original-vs-corrected values, OCR missing/failure/unreadable/ambiguous
sample/depth/unit cases, no fabricated image chemistry, mocked vision consent and
invalid output, alias lookup, exact scope filtering, FTS escaping, citations,
unsupported IDs, source conflicts and all 60 unchanged blocked rules.

No executable crop rule, private deployment, human agronomic acceptance, verified
laboratory authenticity or actual external vision performance is claimed. See
USER_ACTIONS_REQUIRED.md for the separate external/human gates.
