# Final source and conflict resolution

The isolated worktree is `/workspace/EarthSync-final`; branch is
`integration/earthsync-final-stack-v1`. No source PR/worktree was modified.
The initial fetch verified these exact source heads, unchanged from the request:

| Source | PR | Immutable head |
|---|---|---|
| 7H application foundation | #20 | `a7c33cc6b58703501bbba0ceba1bad1d6d42004b` |
| 7I evidence platform | #19 | `b578a6df2764479ff9c9df006cc00e5ddb3ccfa3` |
| 7L complete UI | #21 | `bd8d245b0eae92aab353d852baf05adba5527384` |

The 7L merge base is `5addde741cb9a0efbea9492b2bf8f889d5862517`.
`git log 5addde7..a7c33cc` identified seven newer 7H commits; `git diff`
identified 41 changed files. These were inspected before the true three-way merge:

| Commit | Newer 7H change | Resolution |
|---|---|---|
| `8d88baa` | Windows timezone dependency and platform-specific privacy tests | Retained; combined lock includes tzdata and current photo tests |
| `069c5b5` | Transparent ASGI request-size middleware | Retained unchanged |
| `878d29b` | Inactive device coordinates excluded from assistant, bounded CI stalls | Retained exact assistant selection guard and CI timeout/diagnostics |
| `d051b36` | Browser/Android verification, bounded fixture names, renderer/photo/web fixes | Retained runtime fixes, tests, launcher and historical verification receipts |
| `8eca7af` | Assistant locale UTF-8 on Windows | Retained unchanged |
| `27f67cb` | Wire fixtures explicitly read as UTF-8 | Retained unchanged |
| `a7c33cc` | Passing Windows matrix and final report | Retained as prior-source evidence; not represented as new 7N results |

`git merge --no-ff --no-commit origin/pr21` produced one content conflict:
`app/lib/features/dashboard/dashboard_screen.dart`. The 7L Material 3 dashboard,
responsive layout and action cards were retained. The newer 7H validation-error
branch was restored as a latest-assessment notice, distinguishing invalid,
synthetic and reference-only results. The initial missing provider import was
caught by compilation, fixed, and the complete suite then passed.

Auto-merged overlaps were reviewed against both parent blobs:

- Assistant presentation retained 7L context naming plus the newer 7H guard that
  sends approximate device coordinates only for the active device-selected area.
  Background evidence updates still preserve the draft; selection/language edits
  invalidate old answers. New persisted context follows the verified farm link.
- Photo UI retained 7L gallery/zoom/deletion confirmation and 7H sanitization and
  bounded header parsing. Unsupported Web ImageDescriptor dimension getters were
  not restored. Workspace tokens remain session-only.
- Dashboard climate accessibility, UTF-8 web-engine decoding, NASA client handling,
  browser regression scripts and newer integration tests were retained.
- A formatter change in `test_support/nasa_bridge_checks.dart` is required by the
  selected Dart 3.12 formatter; assertions and opt-in behavior are unchanged.
- The additive 7I branch merged without Git conflicts. Shared routers/launchers
  were not replaced: the private platform runs independently on loopback.

## Toolchain and dependency decision

The original 7H lock requires Dart >=3.13 / Flutter >=3.47, and its CI specifies
Flutter 3.50. 7L added flutter_localizations and used Dart 3.12 / Flutter 3.44,
including SDK-pinned intl 0.20.2 and compatible transitive packages. The direct
Riverpod/router/map/chart/FRB versions remain the reviewed versions.

The 3.50 archive request was unavailable (HTTP 403) and the 3.50 container tag was
absent. The available stable image resolved to 7L's exact recorded digest:
`ghcr.io/cirruslabs/flutter@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8`.
It contains Flutter **3.44.0**, Dart **3.12.0**, framework `559ffa3f75`.

We selected this reproducible toolchain, inspected the lock diff, and verified
`flutter pub get --enforce-lockfile` without altering 7L's lock. The new locale/font
assets remain present. All three Flutter workflows now use 3.44.0 and enforce the
lock; 7H's CI timeout and backend Windows fixes remain. Backend/host Rust stays 1.99.0 / FRB
2.13.0; Android Cargokit resolved Rust 1.100.0, recorded in its build receipt. The platform lock includes the combined backend lock, retaining Pillow
12.2.0 and tzdata rather than downgrading the newer photo/Windows dependencies.

CI now exports compatibility interfaces from the actual integrated HEAD. The
original pinned export mode remains available for historical source verification.

## Final acceptance update: 7J and 7Q

Reviewed and merged complete 7J `d7e43399c9fd296032e64b1c1b5623dbeb70cca6`
(including precision follow-up `d7e4339`, not only initial `06145ee`) and 7Q
`ef9a67ced98c9af98d677a679c9ab1761dc8904a`. Both true merges were conflict-free
and original PRs remain untouched. Applied the separate reviewed 7I precision
patch with `git apply --check` before applying it; retained both regressions and
added an out-of-domain response-coordinate rejection at the same boundary.

7J supplies monthly response coordinate/date/duplicate-key guards, exact response
hashes and confirmed-field succession/fallow rules. Existing 7I duplicate/calendar/
hash protections were verified rather than replaced. The 7N cache-immutability fix
remains in place. Rust binaries/FRB libraries must be rebuilt and hashes refreshed
before these scientific fixes are claimed in execution receipts.

7Q's operations bundle is integrated using the existing two ASGI entrypoints.
Targeted adaptations select Flutter 3.44, include the platform URL in the Web build,
record exact loopback browser/service origins, check run ports, and hash the combined
Python lock. No second API architecture or public proxy was added. Its structured
PASS/FAIL/INCOMPLETE reporting, maintenance exclusion and restart-generation checks
remain. The standalone 7N launcher is a development convenience; the reviewed
operations workflow is the canonical restricted staging/recovery path.
