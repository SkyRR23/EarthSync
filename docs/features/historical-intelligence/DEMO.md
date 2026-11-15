# Local demo and acceptance

Use an isolated checkout and a **new** private state directory. Never point this
branch at a Windows acceptance database or another running installation's state.
Follow the existing `docs/release/RUNBOOK.md` platform/web build and startup flow,
substituting this feature branch's exact reviewed commit. The local API remains
loopback-only; no public hosting or deployment is needed.

For development, install `server/platform-v1/requirements.lock` in a new Python
3.12 environment, build `engine/Cargo.toml --example v03_demo --locked`, and pin
the absolute executable path and SHA-256 with `EARTHSYNC_V03_EXECUTABLE` and
`EARTHSYNC_V03_SHA256`. Set `EARTHSYNC_PLATFORM_DIR` to a new absolute private
directory, `EARTHSYNC_PLATFORM_LOCAL=1` and exact `EARTHSYNC_PLATFORM_ORIGINS`.
Run `uvicorn earthsync.platform_v1.api:app_factory --factory --host 127.0.0.1`.
Build Flutter 3.44.0 Web with `--dart-define=PLATFORM_URL=http://127.0.0.1:<port>`,
`--no-web-resources-cdn --pwa-strategy=none --no-wasm-dry-run`, then run
`python scripts/finalize_offline.py app/build/web` before serving it on loopback.

1. Confirm/select a saved farm, connect it through Farm Evidence, then open
   **Historical Simulation Lab** from Dashboard, Field, Season or Rotations.
2. Select Detailed 2024 and retrieve NASA. Open that archive to inspect daily
   values, monthly charts, missing-day counts and original provenance.
3. Play day/week/month steps, adjust speed, choose a date and validate NASA imagery.
   Soil context retains its actual static version while replay dates change.
4. Retrieve 2025, or request 2015–2025 explicitly for a contextual comparison.
5. Search reference identities; configure previous/current crops for baseline/A/B,
   hypothetical dates, water/drainage/resource assumptions, gap declarations and priorities.
6. Run and save. Change planting dates and verify the corresponding period outputs
   and native chronology change. Water assumptions change declared constraints;
   unsupported water volumes remain unavailable.
7. Reopen/duplicate a result. Select an existing saved comparison to import its
   baseline/A/B and create new historical reassessments without overwriting it.
8. Try as-of mode with a historical decision date. Today’s retrieved archives are
   withheld unless availability by that date is proven.
9. Keep a device copy. Disconnect network/local service and reopen the saved lab:
   only cached series/results are accessible, read only. Reconnect and refresh
   explicitly. Restart services and check original result/source hashes persist.

Synthetic test farms and hypothetical plans must never be presented as real
farmer observations. See VERIFICATION.md for exact runs, failures and limitations.

## Browser reproduction

Prepare an isolated synthetic linked-farm fixture in a private directory and
retrieve its accepted annual NASA windows through the app/API. The fixture JSON
contains `link` (the existing farm-links request) and `farm` (its confirmed server
response). It must never be committed or described as a real farmer observation.

Run the browser drivers with the project's Python environment plus Playwright
and installed Chromium:

```sh
python scripts/browser_historical.py --fixture /absolute/private/farm.json --output /absolute/private/browser
python scripts/browser_historical_empty.py --fixture /absolute/private/farm.json --output /absolute/private/empty-browser
```

Use `--resume-saved /absolute/private/browser/browser-state.json` for a separate
saved-state/as-of/import/fallback follow-up. This is explicitly a resumed test,
not an uninterrupted original journey. Output directories are required to stay
outside the checkout by the existing privacy helper. Keep normal TLS enabled;
use the environment's configured trusted CA rather than bypassing verification.

The final package/source SHA, Windows/Linux download links and integration choices
are in draft PR #33. Continue existing PR #29 Windows acceptance independently;
review this isolated feature against the final-product branch before any explicit
approval to include it in a final main release.

## Reviewed actual-browser frames

Every farm/history/plan in these frames is an explicitly synthetic software-test
fixture. Weather and map/soil source values are real or cached-real source data.
The cropped offline frame was captured directly by the browser to exclude runtime
result identifiers; no values or UI pixels were fabricated.

* [Editable hypothetical baseline/A/B workspace](evidence/scenario-editor.png)
* [Actual 2024/2025 source and Rust comparison](evidence/comparison-2024-2025.png)
* [Two requested image dates with fixed soil context](evidence/dated-imagery-and-static-soil.png)
* [Explicit cached read-only mode](evidence/offline-summary.png)
* [No-cache unavailable state](evidence/no-cache-unavailable.png)
