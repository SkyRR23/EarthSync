# NASA Field Shift demonstration

Use the local combined application built from the reviewed PR #29 head. Never
present the software-test field, photo, farmer reports or short test crop periods
as actual farmer ground truth or validated crop durations. The application has no
approved crop suitability rules and no accepted operational NDVI observation in
this provider scope. Announce those limits plainly.

1. **Confirm a field.** Select the saved software-test field or enter an explicitly
   confirmed real location. Draw/edit/undo a boundary, confirm and reopen it. Show
   that map, records and assessments use the same confirmed revision.
2. **Inspect environmental context.** Open the field's source panel. Inspect the
   real bounded SoilGrids pH cells, original units/depth, nominal 250 m support and
   missing cells. Show the sparse GFS temperature forecast's model and valid
   times. Explain that these are regional modeled products, not farm samples or
   official warnings. The dated true-color basemap is not NDVI.
3. **Show NASA and Rust.** Retrieve historical NASA POWER inputs for a selected
   period. Inspect rainfall and actual Rust FAO-56 reference ET0. ET0 describes
   atmospheric demand over reference grass; it is not an irrigation amount.
   Say whether this request is REAL or CACHED REAL, preserving original retrieval.
4. **Explore three strategies.** Open the saved comparison: a farmer-declared
   existing plan, alternative A and alternative B. The retained browser fixture
   compares rice–mung bean, rice–sesame and rice–groundnut as synthetic exploration
   inputs. Its very short dates deliberately test chronology and an overlap;
   they are not an agronomic example. Declare a real baseline only from an actual
   farmer report or confirmed existing plan. Show source scopes, crop facts,
   priorities, water context, timing findings, missing evidence and local-review
   requirements. Do not call an alternative “best”.
5. **Record what actually happened.** Enter an actual reported crop period and
   retain its source as farmer-reported. Demonstrate the separate confirmation
   before copying a completed period into Rust history. Planned operations are
   kept distinct. Attach a dated observation to an owned sanitized photo.
6. **Follow the season.** Reopen the timeline: reported periods, declared bare/fallow
   periods, unknown gaps, original environmental snapshots and saved assessments.
   A gap does not prove bare soil. Calendar days do not identify biological stage.
   Open the risk center, inspect stale/valid times and explicitly acknowledge a
   dated forecast snapshot. No background alert service is claimed.
7. **Explain and revisit.** Ask the deterministic assistant about the saved
   comparison and evidence; inspect citations and limitations. Switch core labels
   to Burmese and back. Opt in to a saved device copy, disconnect and demonstrate
   read-only cached records with original timestamps. Reconnect before submitting
   drafts or making a new assessment. Restart and reopen persisted records.

Location-free screenshots and sanitized test receipts are retained in `evidence/browser-final/`,
`evidence/browser-7g-tile-verification/` and `evidence/browser-risk/`. The separate
tile run explicitly records a managed proxy certificate exception in Chromium;
it does not establish normal browser TLS trust for tiles. The verification report
identifies exactly which journey steps passed, resumed, failed or remain unavailable.

The final scientific message is: EarthSync makes rotation alternatives and their
supporting evidence understandable while preserving farmer choice and unknowns.
Source-backed crop characteristics do not guarantee nitrogen credits, erosion
control, pest prevention, market access, income or yield.


Map/assistant screenshots containing coordinates and the original full runtime
receipts are deliberately private. The shared-workspace raw archive is
`/workspace/.earthsync-final-private/release-raw`; it is not part of the GitHub
release. Public JSON files are summaries, not replayable raw assessment requests.
