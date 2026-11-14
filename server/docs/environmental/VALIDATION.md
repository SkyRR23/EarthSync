# Validation record

Run in the isolated worktree `/workspace/EarthSync-environmental-context`,
branch `feat/environmental-context-v1`, based on
`e0cdaaf875efb376e3081a66826b4b5e21601c67`. No AGENTS.md was present in the
repository/workspace search. Existing Rust/Flutter/POWER source files have no
diff against that baseline.

Environment tool paths below identify the exact preinstalled toolchains used;
developers may use their equivalent activated Python 3.12 and Rust environments.

From the repository root:

```sh
PATH=/workspace/.earthsync-tools/cargo/bin:$PATH CARGO_HOME=/workspace/.earthsync-tools/cargo RUSTUP_HOME=/workspace/.earthsync-tools/rustup cargo build --locked --offline --manifest-path engine/Cargo.toml --example web_engine
```

Passed; compiled the existing actual Rust example without source changes.
From `server/`:

```sh
/workspace/.earthsync-python/bin/python -m pip check
/workspace/.earthsync-python/bin/python -m ruff check earthsync tests
/workspace/.earthsync-python/bin/python -m ruff format --check earthsync/environmental tests/environmental
PATH=/workspace/.earthsync-tools/cargo/bin:$PATH CARGO_HOME=/workspace/.earthsync-tools/cargo RUSTUP_HOME=/workspace/.earthsync-tools/rustup /workspace/.earthsync-python/bin/python -m pytest -q
```

Passed: no broken requirements, repository-wide Ruff lint, formatting for the
new package/tests, and **110 tests** including existing POWER replay, web-demo
engine routes and the compiled Rust contract consumer. One existing Starlette/
AnyIO deprecation warning is reported. Tests are offline; provider-shaped data
in the new tests are explicitly synthetic software fixtures.

Environmental coverage includes conversions for all eight soil properties,
quantile ordering and missing quantiles, depth mismatch/no interpolation,
source unit/property revisions, response hashes across cache refresh,
exact query/cache identity, independent source failures, per-source attempt
budget, timeouts (including a total deadline), redirects/status/decode/body-size
failures, strict JSON, null/invalid/zero distinction, malformed extremes,
spatial mismatch, half-hour timezone support, fixed-offset daily support,
forecast expiry boundaries, missing run identity, missing QA, farm confirmation,
global points, representative-area mismatch and partial API responses.

The broader formatting command:

```sh
/workspace/.earthsync-python/bin/python -m ruff format --check earthsync tests
```

fails on **pre-existing** formatting of two assertions in
`server/tests/test_web_demo.py`. This was reproduced without modifications:

```sh
git show origin/feat/web-demo:server/tests/test_web_demo.py > /tmp/earthsync-7c-baseline-test_web_demo.py
/workspace/.earthsync-python/bin/python -m ruff format --check /tmp/earthsync-7c-baseline-test_web_demo.py
```

That baseline test remains unchanged. Full repository formatting is not claimed
to pass; existing CI runs that broader check and may fail at this step.

An actual Uvicorn subprocess bound to an ephemeral loopback port was also
started, queried through `urllib.request`, and terminated. Assertions checked
health (`upstream_checked=false`), a JSON POST for the Iowa example, HTTP 200,
`Cache-Control: no-store`, exactly five unavailable envelopes with no scientific
values, and a null diagnosis. Reproduce the same endpoints with the server/curl
commands in [README](README.md) and [CONTRACT](CONTRACT.md). This validates the
local API process only; it is not a browser or live-provider test.

The actual live probe command was:

```sh
/workspace/.earthsync-python/bin/python -m earthsync.environmental.probe --latitude 16.87 --longitude 96.2 --timezone Asia/Yangon --output /tmp/earthsync-7c-provider-probe.json
```

It exited **1**, reporting transport-unavailable for soil and weather and
missing matching QA/pixel support for the three satellite contexts. Its original
output is retained in [provider_probe_blocked.json](provider_probe_blocked.json).
No source response succeeded. Documentation review through the separate web
reader is not a successful backend API request. No browser, Android, farm
ground-truth, crop or scientific validation is claimed.

From the repository root, staged patch integrity was checked with:

```sh
git diff --cached --check
```
