# Historical fallback

Current-source availability and historical archive availability are independent.

| Mode | Display | Allowed actions |
|---|---|---|
| A: accepted current source available | Existing current panels retain valid time/freshness; lab remains explicitly historical | Existing current workflow and separate historical exploration |
| B: current provider fails, historical online available | Failure stays visible in current panels; saved/online historical archive retains original dates | Select/fetch historical periods, simulate and explicitly save |
| C: network/local service unavailable, device copy present | Origin/farm/revision-scoped cached records with original source retrieval and cache-save age | Read-only replay of saved series/results; no automatic write queue |
| D: no valid historical archive/device copy | Informative unavailable/connection state | Explicit safe retry; no synthetic or old unlabeled values |

“Keep for offline viewing” explicitly stores selected source series, selected
simulation and lightweight saved indexes using the existing device-cache adapter.
It never stores credentials or a background mutation queue. An unsaved archive
index is not a promise that all its daily values are present offline. A requested
uncached archive/result shows unavailable. Full series/results remain in private
server SQLite independently of the browser copy.

Edits are disabled for cached snapshots. Offline farmer drafts remain solely in
the existing journal draft workflow; the simulator does not invent another one.
Reconnecting requires explicit refresh/calculation. Missing farm, origin rejection
and permission failures never fall back to old access.

A time selection owns its network request and job. Selection changes abort the
request, cancel the old server job and ignore stale responses. Playback moves
through already selected historical days; imagery must be separately validated
for the selected date. A previous date's image cannot retain a new date label.
