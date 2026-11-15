# Combined submission

The selected primary interface is the latest team-design Flutter app from PR #32 (`50826aa9522285c0e002b96e4e2a5c9b09aa856b`). Its onboarding, four original destinations, Firebase account controls, NASA weather, soil checks and chat remain the primary experience. A fifth Tasks destination and contextual evidence links extend that design.

## Integrated sources

| Source | Commit | Integration |
|---|---|---|
| Latest inspected main | `190f4c527d427c6e009c04c9115e0cb49988801a` | Existing full scientific/backend features |
| Local-first farmer work | `8b61f57` | SQLite, tasks, recurrence, local reminders, soil provenance, dataset registry |
| Historical timeline, PR #33 | `39c276414ae23b05305945424c0728913dad6fce` | Historical simulation and dated evidence workflows |
| Latest bounded NDVI, PR #39 | `9051a26e474cf57184153c839751cbf22c49b9f0` | Bounded viewport and acquisition selection |
| Primary team interface, PR #32 | `50826aa9522285c0e002b96e4e2a5c9b09aa856b` | Primary interface and recent team service additions |

The source lives in a new isolated `earthsync-submission` worktree. The original worktrees and user databases are preserved. No force push or rewriting of teammate branch history is required.

## Where to find features

- Home → My farm tasks & reminders, or the Tasks destination: local task creation, editing, recurrence, completion and reminders.
- Home → Crop rotation decisions, or Next season → Compare crop rotations: three farmer-entered sequences, a selected plan, reason, dated history and offline persistence. Saving a revision creates a new decision. Empty seasons and scientific suitability remain unknown.
- Home → Historical timeline & field evidence: source-backed historical simulation, crop references, assessments, NDVI, private image evidence and detailed strategy comparison.
- Home → Soil properties & map layers: raw properties with source metadata, independent crop suitability, layer/opacity controls, and explicit unavailable states. Farmer soil checks remain accessible.
- The bell opens persisted in-app notifications and preferences. Notes retain the original team workflow and link to field history and task-linked observations.
- Sources & data remains accessible from Home, results and the information area. Your data includes local export and deletion of the added records.

## Storage and connectivity

SQLite stores new tasks, notification history, local field observations, private photos, cached evidence and farmer-selected rotation plans. Existing team SharedPreferences records and optional owner-scoped Firebase backup remain compatible. A stable local ID links the primary farm to evidence tools. A changed boundary creates a new evidence revision without changing that farm's task identity.

CSV remains a dataset interchange/import/export format; it is not the app's primary transactional database. Farm JSON exports include all new structured records and private photos. NASA history continues through the existing validated API/cache with original dates.

Local daily management does not require sign-in or a server. New local task/rotation synchronization and FCM are explicitly unconfigured; they do not block local use. The original optional account backup for the primary farm and Notes remains separate. No global SoilGrids or other large datasets enter the mobile assets.

Fresh NASA data, satellite discovery, AI chat/photo analysis and full historical simulation require their respective configured services. The APK retains the team's existing public HTTPS backend configuration in `app/config/cloud.json`. Publishing combined backend source does not redeploy that service. Advanced private-platform evidence tools remain explicitly unavailable on mobile without a supported service; the local desktop launcher supplies the existing private service for the historical demonstration.

## Build and team verification

At the user's request, the combined submission does **not** rerun the full automated or interactive test suites. Earlier `FARMER_EXPERIENCE_V2.md`/`VERIFICATION.md` results describe the predecessor worktree, not proof of this combined UI. Build/compiler results are recorded separately. The team will perform judging and device acceptance.

Android reminder delivery, permission behavior on a phone, background behavior, optional Firebase synchronization and the newly combined UI are unverified on physical Android. The user explicitly accepted documenting device delivery as unverified. Web system notifications are not promised; in-app reminders reconcile while the app is open.

The `Submission APK` workflow builds a release-mode, debug-key-signed APK for sideload testing. It is not a store-signed release. It includes the source SHA and SHA-256 digest in the downloadable artifact. Its application ID matches the existing team app; preserve/export existing phone data before installation, and do not uninstall a differently signed existing build without backing it up.

The retained scientific feature code and domain tests live under `app/lib/evidence` and `app/test/evidence`. They use one root router and the primary generated Rust bridge. Four obsolete whole-app navigation tests from the replaced shell are superseded by the team shell tests; the retained engine/model/evidence tests are not removed. The Rust scientific engine is unchanged; the primary bridge includes the team's existing ET0 method.

All 60 blocked crop-rule candidates remain blocked. There are no new suitability thresholds, automatic fertilizer/pesticide prescriptions, yield or health scores, or synthetic outage fallbacks.

## Five-minute judging demo

1. **0:00–0:45** Open the team onboarding and select the farmer's field, crop and water answers. Optional account sign-in can be skipped.
2. **0:45–1:30** Open Home and the soil map. Explain the source, model depth/resolution or unavailable state; record a farmer soil check.
3. **1:30–2:30** Open crop rotation decisions. Enter an existing crop sequence and alternatives, choose one, explain the farmer's reason and save the dated decision. Suitability is clearly undetermined.
4. **2:30–3:30** Create a field-check task, edit its due date and repeat schedule, opt into reminders, then complete a task. Open the notification center and preferences. Phone delivery still needs team verification.
5. **3:30–4:30** On the local desktop full-stack demo, open Historical Simulation Lab, select a completed historical interval, retrieve real evidence, inspect timeline dates and compare permitted scenarios. Unavailable provider data must remain unavailable.
6. **4:30–5:00** Disconnect and reopen saved tasks/plans/observations. Show original evidence dates and Sources & data. Export the local records if needed.

The demonstration is a walkthrough script, not a claim that device acceptance was run.
