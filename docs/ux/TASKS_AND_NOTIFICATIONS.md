# Tasks and reminders

`FarmTask` stores a stable ID, local owner, farm ID, category, title, description, civil due date, optional minute of day, IANA time zone, priority, persisted status, creation/update/completion timestamps, recurrence/interval, reminder lead time, manual/template origin, optional observation ID and optional provenance. Overdue is derived from the current time, not a second persisted status. Date-only tasks become overdue at the next midnight in their saved zone.

Categories cover irrigation, soil moisture, crop/pest/drainage inspections, farmer-planned fertilizer, planting preparation/planting, weeds, maintenance, harvest preparation/harvest and custom work. Templates are editable activities; none prescribe an agronomic quantity or scientifically approved schedule.

## Persistence and repetition

`LocalFarmStore` uses SQLite transactions. Complete/skip creates one deterministic recurring successor; repeated completion cannot duplicate it. Reopening retains the original ID. Daily/weekly repetition uses civil dates across DST. Monthly repetition retains the original day anchor through short months. Delete stores a local tombstone and removes the task from active lists. Notifications and export use the same farm identity.

Upcoming reminders for a repeating pending activity are preplanned, while the next task record materializes on completion/skip. The OS queue is bounded to 48 events and at most 90 days/32 generated occurrences per activity. Long recurring schedules need occasional app opening to replenish the queue. Returning after a long offline interval skips the old recurrence backlog while retaining the original missed event and recent occurrences.

## Notification paths

| Path | Implemented behavior | Verification boundary |
|---|---|---|
| In-app center, Android/Web | Due/overdue task events, unread/read/dismissed state, read all, farm/task navigation | SQLite and browser tests; no backend required |
| Android local scheduler | `flutter_local_notifications` 21, inexact idle-capable scheduling, explicit notification permission, boot receivers, stable OS IDs, edits replace schedules, completion/delete cancels | Platform code/build result in verification; real device delivery must be checked |
| iOS/macOS | Same plugin adapter and explicit permissions | Not built or delivered in this Windows session |
| Browser system notifications | Unavailable in this implementation | Center works while open; no Android-style Web background claim |
| Firebase/FCM | Explicitly unconfigured | No credentials, device token registration or server sender introduced |
| Weather warnings | Existing verified warning cards only | Historical NASA/model snapshots never manufacture task or emergency alerts |

Reminders are disabled by default. The farmer opts in under Notification preferences; the device prompt is a separate action. Quiet hours use a visible saved IANA zone and defer events until the quiet window ends. Permission denial retains in-app reminders. Android uses `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED`; exact-alarm permission is not requested. Battery/OS restrictions can delay inexact delivery.

The center reconciles on launch, resume, local changes and a minute clock while open. Event keys are deterministic per series/date/category. Database insert-ignore preserves read/dismissed state on reconnection and restart. Native IDs are allocated once and reused, preventing duplicate pending OS requests.

For a hardware acceptance check: enable preferences/device permission, use Send a test notification, create a future task with a time/zone, disable Wi-Fi/mobile data, close the app and observe delivery. Then verify edit, completion, reboot, quiet hours, denied permission and activity deletion. A successful software scheduler test is not evidence of physical delivery.

Primary package contracts: [local notifications](https://pub.dev/packages/flutter_local_notifications/versions/21.0.0), [timezone](https://pub.dev/packages/timezone), [device time zone](https://pub.dev/packages/flutter_timezone).
