# Record Active Workouts to Apple Health as a best-effort projection

Status: Accepted for 1.6 by Kevin in #27. Rules marked *(spike)* depend on
behavior that the #27 device checks must confirm. Record each result here.

## Decision

When the person turns on **Save Workouts to Apple Health** (default off), Baros
mirrors each Active Workout started on this iPhone into at most one HealthKit
workout. The activity type is `.traditionalStrengthTraining`, the location is
`.indoor`. Like the Workout Live Activity (ADR 0003), the Apple Health workout is
a projection of the Baros workout, never a source of workout state. A HealthKit or
Watch failure can leave Health missing a workout. It can never change, block, lose,
or overwrite a Baros workout. Baros never writes two copies of its own workout. It
doesn't try to detect or avoid workouts recorded by other apps. Running another
workout app at the same time is the person's choice and gives them two workouts,
as it would with any two apps.

### Supported setups

Each one must save exactly one Health workout per finished Baros workout.

| Setup | Who records | Live heart rate |
| --- | --- | --- |
| 1. iPhone only | iPhone session | None, and the UI shows none |
| 2. iPhone + AirPods Pro 3 / Powerbeats Pro 2 / a Bluetooth strap | iPhone session | From the sensor, in the workout header |
| 3. iPhone + Apple Watch with the Baros app | Watch session, mirrored to the iPhone. If the Watch isn't ready in time (out of range, left at home), it falls back to setup 1 or 2 | From the Watch, on the Watch and in the workout header |

### The seam

- **Committed state only.** The recorder observes committed Baros state. It never
  runs inside `ActiveWorkoutEngine`, `WorkoutHistoryMutationService`,
  account-transition, or sync saves. Those saves never wait on it, and it can't
  throw into them.
- **Level-triggered.** Each pass compares a `Sendable` snapshot of the current
  records with the ledger, then acts. It never replays events, so late edits, synced
  tombstones, and reverted deletes all settle to the latest committed state. It
  reads every workout the ledger tracks, not only the visible Active Workout.
- **Missing row vs. deleted workout.** Only a `deletedAt` tombstone deletes a Health
  copy. A missing row (local-data reset or account deletion) only ends and discards
  a live session. Before `LocalDataResetService` deletes rows, it pauses the
  recorder, discards live sessions, and clears the ledger. Saved Health copies stay
  (decision 3). The pause never throws or waits, and the recorder resumes if the
  reset rolls back.
- **The ledger.** A device-local file or `UserDefaults` entry, not a SwiftData model.
  Per workout it holds:
  - the writer (`iPhone`, `Watch`, or `none`) and its state;
  - the Watch attempt token;
  - the last written sync version, start, and end;
  - whether a save was confirmed visible on this device.
- **"Started here."** Active Workouts never sync (ADR 0004), so any workout the
  recorder sees active in the local store was started on this device. The recorder
  writes a "started here" ledger entry the first time it sees one, even while the
  setting is off. Only marked workouts can get a writer, so a completed workout that
  arrives by sync is never written, and the "setting turned on mid-workout" fallback
  has an entry to consult.
- **Unused fields stay unused.** `WorkoutSession.healthLinkID`,
  `LoggedSet.healthLinkID`, and the `HealthDataLink` model stay unused, because the
  first two sync to Convex. HealthKit identity stays on the device.

### One writer per workout

Each workout has at most one writer, recorded in the ledger before that writer can
save. The other device never saves that workout, even as a fallback.

- **iPhone writer** (slices 2–3). An `HKWorkoutSession` + `HKLiveWorkoutBuilder`
  (iOS 26+) starts at the workout's `startedAt`. Metadata is set at start with
  `addMetadata`:
  - `HKMetadataKeySyncIdentifier` = the Baros workout UUID;
  - `HKMetadataKeySyncVersion` = `updatedAt` in milliseconds.

  Recovery can then identify the workout without the ledger.
- **Watch writer** (slices 4–5). Used when the Baros Watch app is paired and
  installed (`isPaired && isWatchAppInstalled`). `startWatchApp(toHandle:)` reports
  only that the launch request went out, so the start takes two phases:
  1. The Watch starts its session and mirroring, then waits.
  2. Before sending a claim, the iPhone records **Watch** as the writer.
  3. It then sends `{workoutID, startedAt, attempt token}` over the mirrored
     session.

  The Watch waits at most a short claim deadline (about 30–60 s). With no claim by
  then, it ends and discards its session. On a claim, it sets the same
  `HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion` with `addMetadata`.

  **Once a claim is sent, the outcome is "Watch or nothing".** The iPhone never
  becomes the writer for that workout.

  If the Watch isn't ready for a claim within a short launch timeout, the iPhone
  becomes the writer and runs its own session. This covers a Watch that is out of
  range, slow to launch, or failed to start. The iPhone records **iPhone** as the
  writer and declines any Watch that shows up later, and the Watch ends and
  discards. A Watch without a claim can never save, so this can't produce a second
  Baros copy. Slice 5 tunes the timeout on Kevin's Watch so a Watch left at home
  falls back quickly. The iPhone never calls builder APIs on a `.mirrored` session.
- **Other workout apps.** Baros doesn't coordinate with them. If another app's
  session ends Baros's session (`HKErrorAnotherWorkoutSessionStarted`), the workout
  is handled like any session that didn't survive. An iPhone-writer workout is saved
  by the fallback at finish. A Watch-writer workout follows "Watch or nothing".

### Lifecycle (driven from the iPhone's committed workout status)

| Committed state | iPhone writer | Watch writer |
| --- | --- | --- |
| Active, visible | Session running | Session running on the Watch, mirrored to the iPhone |
| Completed | Stop, `endCollection(at: endedAt)`, `finishWorkout()` | Durable `finish(workoutID, token, endedAt)` |
| Discarded, missing row, or setting turned off | `discardWorkout()` and end: no workout is saved | Durable `discard(workoutID)` |
| Hidden by sign-out (ADR 0004) | End and discard the live session; the fallback writes it if the original owner finishes later | Discard; no Health copy |
| Write permission revoked | Stop and discard; the workout's writer becomes `none` | Same |

- **The Watch saves only on a `finish` that names its attempt token.** Every other
  ending discards: the End button without a reply, the maximum session age, or a
  status request about a workout the iPhone doesn't know. A lost or reset `discard`
  therefore can't produce a Health copy.
- **Session lifetime.** Both primary writers stop the session and wait for
  `.stopped` before touching the builder. They always call `end()` after one
  bounded finish or discard attempt, even when a save is left to retry. A retried
  save never keeps a session running.
- **Durable commands.** They are sent over the mirrored session and also over
  WatchConnectivity `transferUserInfo` until acknowledged. They are idempotent by
  workout ID and token. Baros completes the workout immediately; the Health result
  stays pending until then.
- **Idempotent saves.** Before any save is retried, and before the fallback runs,
  Baros queries Health for the sync identifier. An existing copy counts as saved. A
  locked-device `finishWorkout` completion with neither a workout nor an error
  counts as success.
- **Errors.** Only authorization-denied and invalid-input errors are terminal.
  Others, such as `HKErrorDatabaseInaccessible` on a locked phone, retry on the next
  unlock or foreground.
- **Maximum session age.** Both writers have one. Past it, the session is
  discarded. An iPhone-writer workout can then still be saved by the fallback at
  finish.
- **Fallback write.** It applies to iPhone-writer workouts with no surviving live
  session at finish: a failed start, a reboot, the setting turned on mid-workout, a
  hidden owner, the age limit, or another app's session taking over. The iPhone
  saves the workout with an offline `HKWorkoutBuilder` from `startedAt` to
  `endedAt`, with the same metadata. It never runs for writer `none` (revoked
  permission).
- **Recovery.**
  - An iPhone-owned session reattaches through
    `UIScene.ConnectionOptions.shouldHandleActiveWorkoutRecovery`, or a
    `recoverActiveWorkoutSession` call at launch.
  - The Watch reattaches through `handleActiveWorkoutRecovery`, re-mirrors, and asks
    the iPhone for the status.
  - The iPhone registers `workoutSessionMirroringStartHandler` at launch.
  - Force-quit behavior *(spike)*.

### Edits and deletes of saved workouts

- **What triggers a replacement.** Only a change to the stored start or end does;
  title edits don't. The replacement version is
  `max(updatedAt in milliseconds, last written + 1)`.
- **Copy missing from Health.** If the ledger recorded a confirmed, visible save and
  the copy is now gone, the person deleted it: it is marked removed and never
  restored. Otherwise the replacement stays pending and retries.
- **Delete.** A tombstone deletes the Health copy with `deleteObjects(of:predicate:)`
  on the sync identifier. Heart-rate samples from the workout stay in Health, and
  the delete copy says so. If the delete is reverted (for example, by sync), the
  workout is saved again with a higher version.
- **iPhone-recorded workouts.** A replacement saves the new times only. It doesn't
  copy heart-rate samples, because copying would duplicate them in Health. The #462
  device check records whether HealthKit keeps the old samples attached to the
  replacement *(spike)*.
- **Watch-recorded workouts.** Propagation happens only if the spike shows the
  iPhone app can replace or delete the Watch app's workout. Otherwise edits and
  deletes aren't propagated in 1.6, and the copy says so.

### Boundaries

- Only the device that recorded a workout writes it. Workouts that arrive by sync
  from another device are never written.
- Nothing read from HealthKit is uploaded to Convex.
- Baros never makes up values. Only the session's sensors write samples (heart rate,
  system-measured energy).
- **Permissions are asked once, in slice 2.** The sheet asks to write workouts,
  heart rate, and active energy (the builder saves those samples, and slice 3 may
  re-add heart rate), and to read heart rate. Later slices never add a second
  permission sheet.
- Live heart rate appears in the workout header only, and only while readings
  arrive. It comes from the Watch over the mirrored session, or, in an iPhone-owned
  session, from AirPods Pro 3, Powerbeats Pro 2, or a strap.
- Known risk, not solved: restoring a backup onto a second phone copies the ledger.

### Open device checks

- Does an iPhone-owned session need `UIBackgroundModes: workout-processing` to keep
  recording with the phone locked? Apple documents the mode for watchOS only. #461
  checks it on a locked phone and adds the key if needed.
- Can the app find its own saved workout by sync identifier without workout read
  permission? The idempotent-save check relies on it. #461 checks it on a device.

## Module boundary

- The lifecycle policy, writer selection, ledger, and version rule live in
  `BarosCore` (Foundation only).
- The Watch shares the small message and state types. A separate package target
  that supports watchOS is added only if sharing needs one.
- The HealthKit, WatchConnectivity, and SwiftUI adapters live in `Baros/` and the
  watchOS target, behind protocols, as `CurrentOwnerAdapters` does.
- `ActiveWorkoutEngine` stays the only path that finishes or discards workouts.

## Not chosen

- **Starting Apple's Fitness workout from Baros:** no public API exists.
- **WorkoutKit:** plans workouts for the Apple Watch Workout app and doesn't record
  one.
- **Saving only at finish:** no live heart rate and no lock-screen or crash
  continuity. It's kept only as the fallback.
- **Reading the Watch's background heart rate after the fact:** too sparse to
  describe a lifting session.
- **Heart rate in the Live Activity:** update budgets and lock-screen health data
  cost more than they add. It can follow later.
- **Sending edits to the Watch over a second command channel:** too much for 1.6.
- **Set logging on the Watch:** belongs to the 2.0 Watch app, which builds on this
  companion.
