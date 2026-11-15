# Android simulation decision support

The primary Android flow is an explicitly labelled historical simulation.
Simulation today starts on the actual calendar day/month within the selected
historical data year. The full year remains visible and can be changed. This
does not relabel archived conditions as present-day observations.

## Rotation

Enter a three-crop existing plan. The new `earthsync.simulation.v1` JSON path
uses the same native Rust bridge ABI and generates two alternatives from five
packaged source-reference profiles (rice, maize, mung bean, sesame, groundnut).
Other baseline crops remain valid inputs, but lack packaged ecological profiles
and remain explicitly unknown. No blocked crop-rule candidate is enabled.

The engine compares historical monthly temperature averages with ecological
reference ranges under a declared season-length assumption. Complete annual
rainfall can be compared with global annual envelopes for a rainfed scenario;
annual rain is not crop-season water supply. The optional family-diversity
objective is a declared planning preference, not a proven pest or soil benefit.
Only comparable known inputs support a preference; otherwise the result states
that superiority is not established. Output reasons, assumptions, source IDs,
source year and exact assessment are retained with a saved decision.

The Android comparison offers an explicit rain-only or irrigated scenario, or
the saved water-supply answer. When climate comparisons are unavailable, a
suggestion can still meet the farmer's selected diversity goal if both complete
sequences have known crop families; it is labelled preference-based, with climate
fit unknown. Missing data are never scored as evidence of a better crop.
Each option shows assumed season dates. Changing the source, field, date,
baseline or assumptions requires a fresh comparison before selecting/saving.

The historical year is an analog repeated across proposed seasons. It is not a
forecast. The interface does not claim yield, profit, field accuracy or validated
agronomic suitability. This is decision exploration using declared assumptions.

## Offline reference

The demo defaults to the clearly labelled included NASA POWER Yangon reference,
16.85 N, 96.15 E. It contains 2016–2025 dated rainfall and modeled root wetness,
derived from the pre-existing captured provider response. The package retains
its original source path and SHA-256. The source label remains distinct from the
user's saved field. An explicit source choice in Weather can select field-loaded
history instead. There is no automatic outage substitution, and existing saved
source choices are retained.

Missing temperature, wind and dates stay missing. No daily extreme is inferred
from a monthly mean. Real-time implementations remain unused by the primary
simulation path; see `app/lib/realtime_unused/README.md`.

## Tasks and observations

Tasks now leads with Rust-generated simulation checks; the old manually managed
activities remain under a separate expansion. Checks incorporate dated reference
rainfall/wetness, reported pests, a watering record and a farmer-reported wet-soil
check. The 30 °C hot-month trigger is an explicit simulation assumption and does
not represent a daily observation or validated crop threshold. No irrigation
amount or pesticide application schedule is invented. A wind advisory requires a
dated wind input, absent from the packaged reference.

Suggested checks can be marked done and undone. These marks and simulated
watering/wet-soil observations are stored locally per field and historical day,
separately from real watering records, and are removed by Delete my data.
Only explicitly simulated notes in the selected historical seven-day window
trigger the simulation pest follow-up; future notes are excluded.

New farmer notes retain their simulation observation date. Existing notes keep
their original dates. “Ask for next steps” sends the selected note text and
available context, not its image pixels, to the configured Groq backend.

## Groq retrieval deployment

`scripts/build_chat_references.py` packages existing attributed crop and health
records into `server/earthsync/chat_references.json`. The server retrieves a
bounded set of crop/topic-matched records and provides original source links.
Records retain scope, review status and limitations. Retrieval does not verify
the model's conclusion; no-match answers are labelled general guidance.

The teammate must deploy the updated Python server for this to run on the hosted
service. The APK cannot configure Groq keys or deploy Cloud Run. See the hosted
backend handoff. No automated or interactive tests are run at the owner's request;
compiler/build results are separate from owner phone acceptance.
