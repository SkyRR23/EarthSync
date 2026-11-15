# Farmer Experience 2.0 verification

Source base: `190f4c527d427c6e009c04c9115e0cb49988801a`. This report records the independently tested local-first implementation before the user's final submission integration. The final submission must retain the friend's PR #32 frontend and add the historical timeline; its combined checks are reported separately.

| Check | Observed result |
|---|---|
| Flutter 3.44 analyzer | No issues |
| Complete Flutter suite, actual native bridge available | 170 passed, 3 opt-in integration skips |
| Python backend and staging, isolated locked environment | 636 passed, 25 explicit external/platform skips |
| Rust engine | 124 passed |
| Rust bridge | 6 passed |
| Flutter Web release | Built; 45 public offline assets prepared |
| Documented PowerShell startup | Ready on checkout-specific loopback ports |
| Actual HTTP smoke | All 9 checks passed |
| Chromium, no HTTP mocks | 23 acceptance stages passed; no page or captured layout errors |
| Android APK attempt | Dependency downloads stalled; not counted as a successful build |
| Android physical delivery | Unverified; user explicitly accepted documenting this limitation |

The browser journey used a clearly named software-test farm and synthetic farmer observations/photos. It verified first launch without sign-in/GPS, task creation and offline completion across reloads, local notes and private photo persistence, due in-app notifications/read history, honest unavailable soil and unknown crop suitability, weather/crop/source destinations, online/offline transitions, widths 320/390/768/1440, persisted dark appearance and an actual JSON export download. Expanded task-control checks are tracked in the final combined candidate rather than implied by these 23 stages.

Python skips cover explicitly opt-in NASA/soil/HLS checks, unavailable audited compatibility paths/v0.3 executable environment flags, POSIX-only fixtures and Windows symlink privileges. Flutter skips are opt-in live integrations. Live agricultural accuracy, a newly retrieved SoilGrids raster, a physical phone, reboot/background notification delivery, Firebase task sync and FCM delivery are not claimed.

The source audit and immutable-catalog check retained all 60 blocked crop-rule candidates and zero executable suitability rules. Large rasters/global scientific databases are excluded from mobile assets. Cached environmental data keeps its original timestamps and query identity. The production Web build uses JavaScript; the existing FRB package reports a WebAssembly dry-run compatibility warning.

Raw local logs, isolated browser profiles, exports and databases remain ignored under `.earthsync-runtime/` or the checkout-specific private state directory. Only sanitized software-test screenshots may be published. The four referenced design images were absent from the supplied attachment; no pixel match is claimed.
