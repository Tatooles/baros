# Workout Graph Sync Design

Issue: [#11 Sync workout sessions, logged exercises, and logged sets](https://github.com/Tatooles/lifting-log-ios/issues/11)

Date: 2026-06-09

## Decision

Expand the existing sync engine from settings and exercises to the full v1 sync graph: user settings, exercises, completed workout sessions, logged exercises, and logged sets.

Workout sync is completed-only for v1. Active workout drafts stay local-only in SwiftData and are never pushed to Convex while the user is in the workout flow. When the user finishes a workout, the completed workout graph becomes eligible for sync through the same outbox used by the rest of the sync system.

The implementation should include a focused rename of the sync layer so the names match the broader responsibility:

- `SettingsExerciseSyncCoordinator` -> `SyncCoordinator`
- `SettingsExerciseSyncClient` -> `SyncClient`
- `ConvexSettingsExerciseSyncClient` -> `ConvexSyncClient`
- `FakeSettingsExerciseSyncClient` -> `FakeSyncClient`
- `SettingsExerciseSyncCoordinatorTests` -> `SyncCoordinatorTests`

The rename should stay mechanical. The behavioral work is workout graph sync, not a general sync rewrite.

## Goals

- Sync completed workout sessions between local SwiftData and Convex.
- Sync logged exercises with correct ordering and parent workout session relationships.
- Sync logged sets with correct ordering and parent logged exercise relationships.
- Keep active in-progress workouts local-only.
- Use the existing outbox for workout graph create and delete intent.
- Push workout graph records in dependency order to avoid child-before-parent writes.
- Pull remote workout graph records into SwiftData so reinstall or second-device setup reconstructs workout history.
- Retry failed sync without duplicating sessions, logged exercises, or logged sets.
- Support deleting completed workouts, including server tombstones after records may have synced.
- Preserve the existing settings and exercise sync behavior.
- Add targeted UI tests for local finish-to-history and delete-from-history flows.

## Non-Goals

- No live cross-device active workout sync.
- No cloud backup of active workout drafts.
- No mid-workout conflict handling.
- No new completed-workout editing UI.
- No broad user-facing sync status, retry, or error recovery UI. That belongs to the next roadmap issue.
- No large sync architecture rewrite beyond the focused naming cleanup and workout graph support.
- No bundled whole-workout Convex mutation. Use the existing per-entity Convex API.

## Architecture

The existing settings and exercise sync path should become the app's general sync path. A single `SyncCoordinator` should own bootstrap, owner claiming, outbox push, remote pull, cursor persistence, retry state transitions, and conflict application for all v1 synced entity kinds.

The sync pass should keep the current shape:

1. On first bootstrap, pull remote changes before uploading local records.
2. Claim eligible local records and ownerless outbox entries for the signed-in owner.
3. Bootstrap local records into the outbox when the bootstrap policy says they should upload.
4. Push pending outbox entries.
5. Pull remote changes again if local changes were pushed or if the initial pull was not already performed.

For workout data, the coordinator should never sync active sessions. Completed workout sessions are the bootstrap target and the normal synced workout entity. Discarded or deleted sessions should only reach Convex when there is explicit outbox tombstone intent, such as a completed workout that may already have synced and is later deleted. Discarding an active draft before finish should remain local-only.

The Convex backend already has tables, validators, upsert mutations, tombstone support, and a full `sync:fetchChanges` query for the workout graph. The iOS client should move from `sync:fetchSettingsExerciseChanges` to `sync:fetchChanges` when the local coordinator can consume and persist workout graph cursors.

## Outbox Behavior

The existing outbox remains the local source of sync intent.

While a workout is active, workout session, logged exercise, and logged set model objects may exist in SwiftData, but they should not create cloud sync outbox entries. When the user finishes the workout, the app records create entries for the completed graph:

- one `workoutSession` create entry
- one `loggedExercise` create entry for each visible logged exercise
- one `loggedSet` create entry for each visible set

If the user discards or deletes the workout before finishing, no Convex sync is needed.

If the user finishes a workout and then deletes it before any create entry has been attempted, the pending creates should collapse away and Convex should never learn about that workout. If any create entry has been attempted, delete intent must remain so a later retry can tombstone any server records that may have been created before the failure or interruption.

When a completed workout that already synced is deleted from History, the app should record delete entries for the session, its logged exercises, and its logged sets. Convex should retain tombstoned records in the change feed so other devices can remove the workout graph locally.

## Push Ordering

Outbox entries should be pushed in dependency order:

1. user settings
2. exercises
3. workout sessions
4. logged exercises
5. logged sets

Within a workout graph, the session must be pushed before its logged exercises, and logged exercises must be pushed before their sets. Parent relationships are represented by stable client UUIDs in the payloads, so retries can be idempotent.

For create and update operations, the coordinator should load the local model, verify owner compatibility, map it to a sync payload, and call the matching Convex mutation:

- `sync:upsertUserSettings`
- `sync:upsertExercise`
- `sync:upsertWorkoutSession`
- `sync:upsertLoggedExercise`
- `sync:upsertLoggedSet`

For delete operations, the coordinator should call `sync:tombstone` with the entity kind, client ID, and best available deletion timestamp.

If an entry fails, the coordinator should mark it failed and stop the sync pass. Later entries should remain pending. On the next run, failed and in-flight entries for the current owner should be returned to pending before retry.

## Pull Ordering

Remote changes should be applied in dependency order:

1. user settings
2. exercises
3. workout sessions
4. logged exercises
5. logged sets

Exercises must be available before logged exercises are applied because logged exercises may point at library exercises. Workout sessions must exist before logged exercises can attach to them. Logged exercises must exist before logged sets can attach to them.

If a child record arrives before its parent because of pagination or cursor timing, the coordinator must not create an orphaned local child. It should defer that child and avoid permanently advancing the relevant cursor past unapplied records. A later pull should be able to apply the child after its parent has arrived.

When applying records, the coordinator should use the existing latest-update-wins conflict resolver with delete preservation. Incoming deletes should not restore local records. Owner mismatch should skip the incoming record rather than overwrite data owned by another account.

## First-Run Bootstrap

Workout graph bootstrap should be remote-first, matching the careful behavior already used for settings and exercises.

On first workout graph sync for an owner:

1. Pull remote changes.
2. If remote workout graph records exist, do not bulk-upload existing ownerless local completed workouts unless they already have explicit local outbox intent.
3. If no remote workout graph records exist, claim eligible local completed workouts and bootstrap them into the outbox.

This avoids accidental duplicate workout history when a user signs in on a device that has local defaults or old local data while the account already has cloud history.

A completed workout created while signed out counts as explicit local intent once it has finish-time outbox entries. When the user later signs in, those entries may be claimed for the owner and uploaded unless ownership rules prevent it.

## Payloads

`SyncPayloads` should add Swift payload and record types for:

- `WorkoutSessionSyncPayload`
- `LoggedExerciseSyncPayload`
- `LoggedSetSyncPayload`
- `WorkoutSessionSyncRecord`
- `LoggedExerciseSyncRecord`
- `LoggedSetSyncRecord`

The mapper should preserve the local model's raw values and timestamps:

- workout session fields: client ID, timestamps, title, started/ended time, duration, notes, reference notes, status, source, source session ID, health link ID, deletion timestamp
- logged exercise fields: client ID, session client ID, exercise client ID, order index, snapshot name, snapshot metadata, notes, reference notes, timestamps, deletion timestamp
- logged set fields: client ID, logged exercise client ID, order index, weight, reps, RPE, placeholder values, set kind, completion state, completed time, notes, health link ID, timestamps, deletion timestamp

Optional parent relationships should be encoded as nullable client IDs. Integer-like values sent through ConvexMobile should follow the existing argument-mapper pattern for Convex-safe numeric encoding.

## Cursor State

`SyncCursorState` should store independent cursors for all v1 synced tables:

- user settings
- exercises
- workout sessions
- logged exercises
- logged sets

It should also track a separate workout graph bootstrap flag, for example `hasBootstrappedWorkoutGraph`, so settings/exercises bootstrap state remains independent from workout graph bootstrap state.

Cursor updates should be conservative. A table cursor should only advance to records that were successfully consumed or intentionally skipped for a safe reason. Missing-parent deferrals should not make a child record unreachable forever.

If Convex returns `ignored_stale`, cursor rewind behavior should apply to workout sessions, logged exercises, and logged sets the same way it already applies to settings and exercises.

## Error Handling

This issue should handle sync correctness and data safety, not broad user-facing recovery UI.

The coordinator should:

- mark the current entry failed when a push throws
- stop the current sync pass after a failed push
- retry failed and in-flight entries on the next run
- avoid creating orphaned pulled records
- preserve delete intent when a server write may already have happened
- reject owner mismatches rather than changing records owned by another account
- keep active sessions excluded even if they have local model changes

The next roadmap issue can add richer user-facing sync status, manual retry controls, and error presentation.

## Testing

Unit tests should cover:

- payload mapping for workout sessions, logged exercises, and logged sets
- Convex argument mapping for nullable values, parent client IDs, and numeric encoding
- outbox creation on workout finish
- delete cascade outbox entries for completed workouts
- delete-before-first-success collapse behavior
- push order: session before logged exercises before logged sets
- retry idempotency without duplicate local or remote records
- remote-first workout graph bootstrap
- pulling a full workout graph into an empty local store
- tombstoning synced workout graphs
- skipping active sessions
- deferring child records whose parents are missing
- cursor persistence for workout tables
- `ignored_stale` cursor rewind for workout entities

Convex tests should cover:

- workout session, logged exercise, and logged set upserts
- tombstones for all workout graph entity kinds
- owner isolation
- full `fetchChanges` records and per-table cursors
- stale upsert and tombstone idempotency
- parent client ID fields round-tripping through the change feed

UI tests should cover:

- completing a simple workout through the app and verifying the workout appears in History
- deleting a completed workout from History and verifying it disappears locally

A sync-backed UI test is optional. It should be added only if the existing test infrastructure can authenticate or fake sync cleanly without building a large UI-test-only sync harness in this issue.

## Manual QA

Manual verification should include:

- finish a workout while offline, restore connectivity, sync, and verify it appears in Convex and local History
- sign in on a fresh install or second device and verify the completed workout history reconstructs with exercises and sets in the correct order
- delete a synced completed workout and verify the deletion propagates after sync
- finish a workout and delete it before any sync attempt, then verify Convex does not receive the workout
- confirm active in-progress workouts do not appear in Convex while they are active
- confirm existing settings and exercise sync still works after the rename and expanded coordinator behavior

## Open Implementation Notes

The existing backend already exposes the required per-entity workout graph API. Implementation should start by renaming the local sync types, then extending payloads and client methods, then expanding coordinator behavior and tests.

If missing-parent deferral is awkward with the existing cursor shape, prefer a small explicit pending-remote-change mechanism or conservative cursor rewind over creating local orphans. The chosen implementation must make the retry behavior testable.
