# EarthSync Farmer Experience 2.0

This implementation is in the isolated `feat/earthsync-local-farmer-experience-v2` branch. Source base: `190f4c527d427c6e009c04c9115e0cb49988801a` (`origin/main` at the source audit and final fetch). It extends the integrated farmer application and its existing FastAPI/Rust contracts. PR #32's checkpoint `004cb529fb81dfab51b9169768eb931318b51531` belongs to a different lineage. That team's branch advanced to `50826aa9522285c0e002b96e4e2a5c9b09aa856b` during development; see the handoff for its separate changes.

## Farmer workflows

- Home: selected farm, actual farmer-reported crop, saved boundary area, soil map, today's activities, upcoming/overdue activity, source retrieval state and notification count.
- My Farm: soil-first map plus the existing field evidence, laboratory, NASA climate, assessment and photo workflows.
- Weather: current/forecast providers remain distinct from dated historical NASA POWER records. Unavailable inputs stay unavailable.
- Tasks: actual local creation, editing, completion, reopening, skipping, canceling, deleting, postponing, repeating and calendar/day filters.
- Crops: existing crop knowledge, history and rotation comparison remain reachable. Record a current crop through field records or the existing journal.
- Notes: private local observations and photos; a follow-up task can link to an observation. The existing server journal and evidence remain accessible.
- Notifications: persisted read/dismissed state, preferences and linked task navigation. Android scheduling is an optional device capability, independent of a backend.
- Sources & Evidence: source explanations, original links, retained result provenance, and server dataset installation status.
- Account & privacy: existing controls plus local export and selected-farm activity deletion.

Phone navigation has five destinations and a menu for additional tools. The desktop sidebar uses the same destinations. Existing deep links remain registered; the prior dashboard remains available at `/climate-overview`.

## Design decisions

Design read: a calm farm companion with cream surfaces, forest-green navigation, a field overview, clear task actions and evidence behind a tap. ENERGY 2 / RHYTHM 2 / MOTION 1. Semantic colors, spacing and breakpoints live in `app/lib/design/tokens.dart`; the same theme supports light and dark appearances.

The contour motif identifies land without suggesting a measured property. Actual farmer-saved photographs can appear in the overview. No stock or generated farm-health illustration was introduced. Existing bundled fonts and their licenses are retained. Soil color is a raw numeric pH legend, never crop suitability. Native Material controls provide focus, disabled states, keyboard semantics and labeled actions.

The attachment supplied to this session contained the replacement text prompt only. The four referenced image files were unavailable. The written cream/green direction guided implementation; a pixel comparison or before/after comparison against those missing images is not claimed. Screenshots in `screenshots/` are actual Chromium renders with clearly named software-test farm inputs.

## Start locally on Windows

```powershell
cd D:\Nasa_spaceApp\earthsync-farmer-experience-v2
.\start-earthsync.ps1
```

The existing launcher builds the app, uses a checkout-specific virtual environment, chooses available loopback ports, prints the URL, and supervises only its own services. `stop-earthsync.ps1` stops that instance. `test-earthsync.ps1 -Full` runs the existing full-stack checks. `scripts/local/earthsync.ps1 status` prints the running URL.

Flutter 3.44 and Python 3.12 are the pinned development tools. Set `EARTHSYNC_FLUTTER` to the Flutter executable if necessary. Normal first launch offers local onboarding without sign-in; setting `EARTHSYNC_JUDGES_DEMO=true` before a rebuild retains the optional public Ames reference entry point.

See [verification](VERIFICATION.md), [local-first boundaries](LOCAL_FIRST_ARCHITECTURE.md), [tasks](TASKS_AND_NOTIFICATIONS.md), [soil behavior](SOIL_MAP_BEHAVIOR.md) and [handoff](INTEGRATION_HANDOFF.md).
