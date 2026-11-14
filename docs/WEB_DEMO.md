# Browser demo

This branch combines the latest fetched Flutter live-NASA integration, NASA
POWER backend, Rust v0.2 and local Android fixes. The existing farmer screens are
retained. Browser requests run the actual shared Rust engine as a local process;
this is not WebAssembly or the Android FFI bridge.

From the repository root in PowerShell:

```powershell
python -m venv server/.venv
server/.venv/Scripts/python -m pip install -e ./server pytest==9.0.1 pytest-asyncio==1.3.0
./Run-WebDemo.ps1
```

After building once, `./Run-WebDemo.ps1 -SkipBuild` starts the existing build.
The server binds only to loopback. This local testing host is not a production
deployment. Keep it running while testing the browser.

- `http://127.0.0.1:8080/`: real NASA retrieval, response validation and shared
  Rust calculations, with provenance and errors. Select a sample field, answer
  the questions and analyze the historical window on Review.
- `http://127.0.0.1:8080/?climate=captured`: explicit offline replay of the
  captured real NASA response through Rust. Use the sample field (16.85, 96.15)
  and February 2024. Other fields/periods are rejected rather than relabeled.
- `http://127.0.0.1:8080/?engine=mock`: presentation-only fixture mode. No Rust
  or live climate claim applies to this explicit mode.
- `http://127.0.0.1:8080/docs`: backend and real Rust integration/v0.2 API
  workbench. GET `/api/demo/synthetic-v02` returns the engine's synthetic test
  request, which can be pasted into POST `/api/engine/v02`. It is test evidence,
  not a validated crop recommendation. Invalid input returns engine errors.

The latest Flutter flow consumes the legacy integration envelope. Rust v0.2 is
available for real API testing; its additional factors are not yet rendered by
the farmer screens. Live climate has no verified crop profiles or rotation
recommendations, so missing recommendations remain unavailable. Use the explicit
mock mode only to preview the existing scenario-card design.

Verification:

```powershell
cargo test --locked --manifest-path engine/Cargo.toml
server/.venv/Scripts/python -m pytest server/tests
```

NASA/map requests require internet access. A live failure is shown as an error;
there is no automatic captured-data or mock substitution. Android-native loading,
permissions and device performance still require Android testing.

## Local verification on 14 November 2026

- Rust engine: 82 tests passed; native bridge: 5 tests passed.
- Python: 48 tests passed, including actual Rust endpoint execution, bounded
  bodies, malformed input, fixed process arguments and timeout cleanup.
- Flutter: 27 tests passed, one opt-in live-network test skipped. Static analysis
  passed with 22 existing informational Material-import deprecations.
- The opt-in native Flutter suite was then run separately against the local
  backend with `RUN_LIVE_NASA=true`: all 5 tests passed, including real live NASA
  through the actual native bridge and Flutter climate widgets.
- Flutter web release build passed. The served index returned HTTP 200.
- Live NASA retrieval and the web-service Rust endpoint returned a real generated
  result for the sample point, February 2024: 0.04 mm and 28.03655172413793 deg C.
- Browser visual verification is incomplete: in-app browser initialization timed
  out, then Windows computer use refused to continue because it could not
  determine the current browser URL confidently. No result-screen claim is made.
- Ruff could not be installed locally: pip repeatedly stalled downloading the
  14.3 MB `ruff==0.14.5` wheel; the alternative PyPI metadata download timed out
  after 20 seconds with 39,962 of 43,340 bytes. Ruff checks remain unverified.
  When the connection permits, run:

  ```powershell
  server/.venv/Scripts/python -m pip install ruff==0.14.5
  server/.venv/Scripts/python -m ruff check server/earthsync server/tests
  server/.venv/Scripts/python -m ruff format --check server/earthsync server/tests
  ```

To finish manual browser verification, open the live demo, select the sample
field, complete the questionnaire and analyze February 2024. Check that the
climate tab displays the Rust totals and NASA provenance. Repeat with the explicit
captured link and check its offline-replay label. Stop the service to confirm
that a new analysis shows an error rather than silently substituting a fixture.
