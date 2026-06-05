# Local Sync Metadata and Outbox Design

## Context

GitHub issue #9 covers the local sync foundation for Lifting Log. The app already has SwiftData models with stable UUIDs, `createdAt`, `updatedAt`, and `deletedAt` tombstones for the v1 sync scope. Convex schema and authenticated sync APIs already exist, but this issue should not implement network push, network pull, sync UI, or remote conflict resolution.

The goal is to add durable local metadata so future sync work can safely discover what changed locally, retry failed work after relaunch, and avoid duplicating remote records.

Account switching behavior is tracked separately in GitHub issue #42. This design only keeps room for account-aware sync metadata; it does not define account-switching UX.

## Scope

This issue includes:

- A SwiftData outbox model for pending local sync operations.
- String-backed sync operation and status types.
- A focused recorder service for create, update, delete, retry, failure, completion, and bootstrap state changes.
- Tests for local outbox persistence and state transitions.

This issue excludes:

- Convex upload or download calls from iOS.
- Sync worker scheduling.
- User-facing sync status UI.
- Remote conflict resolution.
- Account-switching UX or data-transfer policy.

The v1 syncable entities are:

- `UserSettings`
- `Exercise`
- `WorkoutSession`
- `LoggedExercise`
- `LoggedSet`

`WorkoutTemplate`, `HealthDataLink`, and `SeedMetadata` remain excluded from v1 sync.

## Architecture

Add a `SyncOutboxEntry` SwiftData model under `LiftingLog/Core/Sync/` and include it in `LiftingLogSchema.models`.

Each entry represents one local entity that needs future sync work. It should contain:

- `id: UUID` as the local outbox entry identifier.
- `entityKindRaw: String` for the synced entity kind.
- `entityID: UUID` for the local domain record identifier.
- `operationRaw: String` for `create`, `update`, or `delete`.
- `statusRaw: String` for queue state such as `pending`, `inFlight`, `failed`, and `completed`.
- `ownerTokenIdentifier: String?` for future account-aware sync. Signed-out entries are unowned.
- `createdAt: Date`
- `updatedAt: Date`
- `lastAttemptAt: Date?`
- `attemptCount: Int`
- `lastErrorMessage: String?`

Add string-backed Swift types for:

- `SyncOperation`: `create`, `update`, `delete`
- `SyncOutboxStatus`: `pending`, `inFlight`, `failed`, `completed`

Add a `SyncOutboxRecorder` service that owns all queue mutation logic. App features should not hand-roll outbox state transitions.

## Recording Local Changes

When app code creates, updates, or tombstones a syncable entity, it should record sync intent in the same user action flow that saves the domain model. The preferred implementation is to mutate the domain model and outbox in the same `ModelContext` before one save. If a call site must save internally, it should roll back on failure so a failed domain save does not leave misleading outbox state behind.

For create:

- If no entry exists for the entity, create a pending `create` entry.
- If an entry already exists, keep the strongest operation according to the coalescing rules below.

For update:

- If no entry exists, create a pending `update` entry.
- If a pending `create` already exists, keep it as `create`.
- Refresh `updatedAt`, clear stale error text, and leave retry metadata available for future sync code.

For delete:

- If no entry exists, create a pending `delete` entry.
- If an unattempted pending `create` exists, remove the entry because the record never left the device.
- If the existing `create` was ever attempted, in flight, failed, or otherwise ambiguous, convert the entry to `delete`.
- If an `update` exists, upgrade it to `delete`.

This refined delete rule keeps the queue clean for purely local create-then-delete actions while preserving tombstone safety when a prior upload may have reached Convex.

## Coalescing Rules

The outbox should keep at most one active entry per entity kind, entity ID, and owner scope. Repeated edits before sync runs should update one entry instead of creating a long list of operations.

Operation precedence:

- `create` plus later `update` remains `create`.
- `update` plus later `update` remains `update`.
- `update` plus later `delete` becomes `delete`.
- Attempted `create` plus later `delete` becomes `delete`.
- Unattempted pending `create` plus later `delete` removes the entry.

The future sync worker should send the latest local record contents when handling `create` or `update`, so preserving every intermediate edit is unnecessary.

## Bootstrap

Add a callable bootstrap method that scans existing local records and enqueues pending work for v1 syncable entities without duplicating existing outbox entries.

Bootstrap should:

- Include `UserSettings`.
- Include `Exercise` records, including archived and tombstoned records.
- Include completed and discarded `WorkoutSession` records.
- Include `LoggedExercise` and `LoggedSet` records linked to sync-eligible workout sessions.
- Skip active workout sessions and their child graph because active workouts stay local-only for v1.
- Leave existing outbox entries intact and avoid duplicates.

Bootstrap should not run automatically in this issue. It exists so later sync work can safely queue data created before sign-in, before sync was enabled, or before the outbox model existed.

## Retry State

The recorder should provide methods future sync code can use to manage local retry state:

- Mark an entry in flight with updated attempt metadata.
- Mark an entry failed with `lastAttemptAt`, `attemptCount`, and `lastErrorMessage`.
- Return a failed entry to pending for retry.
- Remove an entry after successful remote acknowledgement.

Marking an entry in flight should increment `attemptCount`, set `lastAttemptAt`, and clear stale error text. Marking failure should store the error text while preserving the attempt metadata from the in-flight attempt.

After a future remote acknowledgement succeeds, the recorder should remove the outbox entry. The outbox is a work queue, not an audit log. `completed` may exist as a status value for short-lived state transitions or tests, but normal pending fetches must exclude completed entries.

## Error Handling

Recorder methods should throw SwiftData fetch/save errors to the caller. They should not swallow persistence failures or pretend sync metadata was recorded when it was not.

Existing UI save flows can continue showing save failures through their current error paths. This issue does not add sync-specific user-facing errors.

## Tests

Add focused unit tests for:

- Persisting `SyncOutboxEntry` through SwiftData save and fetch.
- Recording create, update, and delete operations.
- Coalescing update into pending create.
- Removing an unattempted pending create when the entity is deleted.
- Converting an attempted or failed create into delete when the entity is deleted.
- Upgrading update to delete.
- Marking failure with attempt metadata and error text.
- Returning failed entries to pending for retry.
- Bootstrap creating entries for existing v1 syncable records.
- Bootstrap avoiding duplicate entries.
- Bootstrap skipping active workout sessions and their child graph.

Add targeted integration-style tests around existing app flows where practical:

- Creating, editing, and deleting an exercise records the expected outbox intent.
- Changing settings records update intent.
- Finishing a workout records sync intent for the completed workout graph.
- Deleting workout history records delete intent for the session and child graph.
- Active workout draft edits do not become bootstrap-eligible v1 sync work.

No Convex network tests are needed for this issue.

## Acceptance Criteria

- The local SwiftData schema includes a durable outbox model.
- Local sync operations can be recorded and coalesced through a single recorder service.
- Retry/failure state survives app relaunch.
- Existing local data can be bootstrapped into pending outbox entries on demand.
- Active workout drafts are not bootstrapped for v1 sync.
- Tests cover the local state machine, bootstrap behavior, and practical recorder integration points in existing app flows.
