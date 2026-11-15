# Android farmer-first update

The Android app now starts with a three-part introduction, including a route to
general crop chat without a saved field. Returning users see it once and can
reopen it from Home. Existing answers and records are retained.

Native Home shows field setup, weather, tasks, rotation planning, chat and records.
Advanced soil/history/source tools remain available under More field tools.
The browser retains the existing HomeTab and welcome route. Native forecast
bars retain dates, millimetres, missing values and retrieval date; proposed crop
sequence diagrams do not imply validated suitability or predicted benefits.

Groq already serves `/api/v1/chat`. Native requests now select `farmer_first`
instructions; existing requests retain their existing mode. Deploy the updated
Python backend to activate that prompt on the hosted service. Updating an APK
or merging GitHub source does not deploy the existing Firebase-hosted backend.
The API key remains a backend setting; it is not bundled into the APK.

No automated or interactive tests were run for this update, at the owner's
explicit request. GitHub Actions compiles the sideload APK; compilation is not
phone acceptance. The prior APK is at:
https://github.com/SkyRR23/EarthSync/releases/download/submission-20261115-eeca926/EarthSync-submission.apk

## Owner phone review

1. Install the update without deleting existing data. If Android reports a
   signing mismatch, stop and report it; do not uninstall before exporting data.
2. Walk through the introduction at a normal and enlarged text size. Try both
   field setup and general chat. Reopen the app and confirm saved records remain.
3. Check Home, weather dates/rain bars/missing values, Records and Tasks.
4. Enter three crop sequences, inspect their season diagrams, save and reopen.
5. Ask “How do I grow rice?” with no field, then a question about your saved
   field. Turn off connectivity and try retrying a failed question.
6. Open advanced tools and confirm they remain reachable. Test reminder delivery
   separately on the phone; no delivery claim is made by this update.

The original release uses a build-environment debug signing certificate. A newly
built APK may need the original signing material to install as an update.
