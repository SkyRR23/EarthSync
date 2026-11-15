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
