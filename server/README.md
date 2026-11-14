# EarthSync NASA POWER backend — Milestone 4A

Python 3.12+; FastAPI climate transport and normalization only. No crop suitability,
soil estimates, forecasting or agricultural thresholds. Current engine contract
was read at main commit `1ea3df7b09637cf8162f834411d830aa8621590c`.

```sh
cd server
python -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
.venv/bin/python -m pytest -q
.venv/bin/python -m uvicorn earthsync.api:app --host 127.0.0.1 --port 8000
```

Activate Rust (cargo on PATH) before pytest to also execute the cross-language
contract test; it compiles an external consumer against `../engine`, without editing
engine files. Otherwise that one test is explicitly skipped. It needs cached Rust
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

See [v1 proposal](docs/API_V1.md), [source methods and live verification](docs/NASA_POWER.md),
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
backoffs on transport errors, 429 and selected 5xx. Windows are limited to 24
months and each chunk to one calendar year; decompressed response size is capped
at 4 MB. No redirects, TLS bypass, raw upstream errors or negative caching.
