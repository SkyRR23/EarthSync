# EarthSync NASA POWER backend — Milestone 4A

Milestone 7H unified application: [setup, endpoints, Android and verification](../docs/integration/README.md).

Python 3.12/3.13; FastAPI climate transport and normalization. No crop suitability,
soil estimates, forecasting or agricultural thresholds. Current engine contract
was read at main commit `1ea3df7b09637cf8162f834411d830aa8621590c`.

```sh
cd server
python -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
.venv/bin/python -m pip check
cargo build --locked --manifest-path ../engine/Cargo.toml --example web_engine
.venv/bin/python -m pytest -q
.venv/bin/python -m uvicorn earthsync.api:app --host 127.0.0.1 --port 8000
```

Activate Rust (cargo on PATH) before pytest to also execute the cross-language
contract test; it compiles an external consumer against `../engine`, without editing
engine files. Otherwise those contract tests are explicitly skipped. Web endpoint tests require
the compiled `web_engine` example and fail if it is missing. It needs cached Rust
dependencies (`cargo fetch --locked` in engine) because it runs offline.

Internal readiness requests:

```sh
curl --fail http://127.0.0.1:8000/api/v1/health
curl --fail 'http://127.0.0.1:8000/api/v1/environment/season?latitude=16.85&longitude=96.15&start_year=2023&start_month=11&end_year=2024&end_month=2'
```

Health is local liveness, not a NASA availability claim. No credentials are required.
`.env.example` documents Uvicorn options; no dotenv loader is used. Dependencies
are pinned in pyproject.toml; `requirements.lock` records the tested transitive
resolution. To reproduce that resolution first install `pip install -r requirements.lock`,
then `pip install --no-deps -e .`. Network destinations: PyPI for installation;
`power.larc.nasa.gov` for live retrieval. No automatic startup calls NASA.

See [Windows/USB/Wi-Fi runbook](docs/WINDOWS_RUNBOOK.md),
[reliability verification](docs/RELIABILITY_VERIFICATION.md), [v1 proposal](docs/API_V1.md), [source methods and live verification](docs/NASA_POWER.md),
and [owner questions](docs/INTEGRATION_QUESTIONS.md). OpenAPI is generated at
`/openapi.json`; `/docs` offers local interactive documentation.

P0 is a small single-process service: 128 cached windows, one-hour TTL, successful
responses only, exact coordinates (no rounding), no stale fallback. Cache hits
preserve the original retrieval timestamps. Cache and processes do not survive
restarts; multiple workers have independent caches. A per-process lock serializes
misses to bound provider load. This is not a production distributed rate limiter;
public deployment needs ingress concurrency/rate limits and a privacy/retention
policy for locations. Default bind is loopback. NASA request timeout is 20 seconds
(5 seconds connect), at most three attempts per annual chunk, 0.25/0.5 second
backoffs on transport errors, 429 and selected 5xx. A 70-second deadline bounds
the entire multi-year retrieval; the HTTP route bounds cache wait plus retrieval
to 80 seconds. Windows are limited to 24
months and each chunk to one calendar year; decompressed response size is capped
at 4 MB. No redirects, TLS bypass, raw upstream errors or negative caching.

## Live verification and CI

NASA POWER live retrieval succeeded on 14 November 2026. The committed
`examples/nasa_power_real.json` contains a real normalized February 2024 response
at 16.85 N, 96.15 E: 0.04 mm total precipitation and 28.03655172413793 °C mean
T2M, with both variables complete across 29 days. This is modeled gridded
historical climate, not a direct farm measurement. See the source review for
limits and reproducible smoke commands.

`.github/workflows/python-backend.yml` independently installs the pinned Python
resolution, checks dependencies and Ruff, fetches Rust packages, then runs
network-independent backend tests including a compiled Rust consumer and replay
of the real capture. No test contacts NASA. Run the same checks from `server/`:

```sh
python -m pip check
python -m ruff check earthsync tests
python -m ruff format --check earthsync tests
python -m pytest -q
```
