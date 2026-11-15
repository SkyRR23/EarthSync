# API reliability verification — 14 November 2026

Worktree: `EarthSync-api-reliability-v2`; branch `fix/api-reliability-v2`.
Baseline: freshly fetched `feat/web-demo`,
`e0cdaaf875efb376e3081a66826b4b5e21601c67`. All edits are in this task's
worktree. No dashboard, crop algorithm, image processing or Rust interfaces
were changed. Region examples are public validation points, not service limits.

## Request trace

1. `app/lib/state/providers.dart` chooses the web HTTP engine by default in a
   browser, the native Rust bridge on Android, or the explicit `engine=mock`
   presentation fixture. No error-triggered mode substitution exists.
2. `NasaPowerClient.fetch` sends the six climate query parameters to
   `/api/v1/environment/season`. Native defaults to port 8000; web uses its
   page origin (demo port 8080). Its current timeout is 90 seconds. Location
   and historical window validation happen before retrieval.
3. `server/earthsync/api.py` validates the request and checks the bounded exact
   query cache; `PowerProvider` requests daily NASA POWER point data in annual
   chunks. It validates MERRA-2 lineage, units, LST, fill sentinel and intervals.
   The complete retrieval is bounded to 70 seconds and the API/cache wait to 80.
4. Monthly normalization requires every daily value independently per variable:
   PRECTOTCORR `mm/day × 1 day` summed to `mm`; mean T2M `C` mapped to `deg_c`.
   Missing/fill/invalid days yield null monthly values and explicit coverage,
   never favorable conditions. The full provenance envelope remains a sidecar.
5. Flutter validates the returned schema, exact selected field/window and
   provenance. The web builder posts the existing integration request to
   `/api/engine/integration`; native calls the existing FFI bridge. The demo
   executes `web_engine[.exe]` with fixed arguments and pipes, with no shell or
   fallback fixture. The optional `v02` route passes `--v02` to the same binary.
6. The server validates the existing Rust envelope before forwarding it. Valid
   domain errors remain HTTP 200 for Flutter compatibility; HTTP/process
   failures have safe machine-readable error codes. Flutter retains the NASA
   sidecar, farmer input, Rust input and Rust output in its integration trace.
   The current Flutter climate client renders generic non-200 errors; detailed
   server codes are available through the API/network response.

Approximate user location, farmer-confirmed field and optional photo metadata
are not combined by this backend. NASA data are modeled regional context,
not observed field evidence, forecasts or crop recommendations.

## Failing-before / passing-after evidence

Before implementation, the initial 11 cases in `tests/test_reliability.py` gave
**9 failures, 2 passes** on the baseline: indistinguishable network/timeout
codes, malformed/wrong engine output accepted or raised unhandled exceptions,
engine launch `OSError` unhandled, and no explicit diagnostic. Those cases now
pass. Follow-up tests cover process failure without replacement, timeout cleanup,
bounded queue/API/provider deadlines, failed-cache exclusion, global coordinates,
chunked provider bodies, captured-real Rust execution, incomplete coverage and
rejection of a newly captured real GEOS-IT response.

Final offline verification on Linux:

| Check | Result |
| --- | --- |
| Python 3.12.14, full backend suite with Cargo available | 74 passed, no skips |
| Python 3.13.18, same pinned lock, full suite with Cargo | 74 passed, no skips |
| Actual compiled Rust engine suite, including integration/v0.2 | 82 passed |
| Ruff check and format | Passed |
| Python 3.13 installed dependency compatibility (`uv pip check`) | Passed |
| `git diff --check` | Passed |

Both Python suites emit the existing Starlette/AnyIO `BlockingPortal`
deprecation warning. It does not fail the tests. Independent mock transports and
raw real captures are used explicitly; these offline tests do not contact NASA.
Windows and Python 3.12/3.13 CI matrix coverage is added, not represented here as
an already completed Windows run.

Commands from repository root after installing the locked backend and putting
Cargo on PATH (see the Windows runbook for interpreter setup):

```sh
cargo build --locked --manifest-path engine/Cargo.toml --example web_engine
cargo test --locked --manifest-path engine/Cargo.toml
cd server
.venv/bin/python -m pytest -q
.venv/bin/python -m ruff check earthsync tests
.venv/bin/python -m ruff format --check earthsync tests
cd ..
git diff --check
```

## Real HTTP and live provider checks

The task ran separate actual Uvicorn services with access logs disabled:

```sh
# From server/, separate terminals:
.venv/bin/python -m uvicorn earthsync.api:app --host 127.0.0.1 --port 8000 --no-access-log
EARTHSYNC_DIAGNOSTICS=1 .venv/bin/python -m uvicorn earthsync.web_demo:app --host 0.0.0.0 --port 8080 --no-access-log
```

The HTTP probe started at `2026-11-14T09:15:20Z`. The host's own non-loopback
address was used in addition to loopback, with direct local connections
(`httpx.Client(trust_env=False)`). A later default `curl` request through the
environment proxy returned 403 for that private address; `curl --noproxy '*'`
returned 200. This was proxy routing, not a server/NASA or HTTP-policy error.
No proxy credentials were printed. Results:

- Health returned 200 on loopback port 8000, localhost port 8080 and the host
  address on 8080, always `upstream_checked:false`.
- Explicit NASA diagnostic returned 200 with live transport, MERRA-2 metadata
  and complete daily coverage. The separate integration diagnostic returned
  200 with `rust_execution:passed`; it executed the actual compiled binary,
  SHA-256 `47ed0f2c528dbbfad4283035f58a9779917a8629674a17274d6c737b673d9931`.
- A live February 2024 request at the public Yangon point produced a cache miss
  followed by a hit, preserving the original provenance. The modeled gridded
  MERRA-2 full-month precipitation was 0.04 mm; the committed normalized
  `examples/nasa_power_real.json` documents the same point/window, units,
  spatial support, limitations and daily coverage. This is not scientific
  validation or a direct field measurement.
- A live October 2026 request at the public Iowa point through the host address
  returned 502 `UPSTREAM_SOURCE_CHANGED`. Direct NASA returned 200 with
  `sources:["GEOSIT"]`. This was a lineage-contract rejection, not a transport
  or HTTP policy failure. The exact raw capture and retrieval metadata are
  committed separately from the MERRA-2 replay.
- Captured real February 2024 evidence was retrieved from the explicit capture
  route, placed in a climate-only `supplied_data` integration request and
  posted through the host address to the actual Rust endpoint. It returned
  the expected 0.04 mm; no crop profiles or scenarios were invented.
- Posting `{}` to the real Rust endpoint returned its original `INVALID_JSON`
  domain error, not a successful fixture.

The final server was restarted after the last code edits and its live integration
diagnostic was repeated successfully. These checks establish actual HTTP,
provider retrieval, validated historical data and real Rust execution on Linux.
They do not establish the complete Flutter UI/device flow.

## Explicit limits and remaining owner work

No Flutter SDK, Windows runtime, physical Wi-Fi client or Android device was
available in this environment. No browser UI, Android permission/FFI,
`adb reverse`, Windows firewall or PowerShell execution success is claimed.
The existing Flutter `?engine=mock` UI was traced in source but not run here;
its presentation-only behavior remains for browser verification. Synthetic
backend/Rust tests are independent of that UI mode. Follow the runbook's
separate live, replay, mock, second-device and USB checks.

A same-host request to a non-loopback address does not establish external LAN
reachability. No already-fixed HTTP policy was changed. Recent GEOS-IT support
requires joint review of the supplied source-verified contract proposal; the
adapter stays unavailable for unsupported lineage. No source labels, crop
requirements, scores, confidence percentages or yields were invented.
