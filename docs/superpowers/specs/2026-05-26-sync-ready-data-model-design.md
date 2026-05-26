# Sync-Ready Data Model Design

## Context

Issue #4 covers Phase 1 of the release roadmap: prepare the local SwiftData model for future Convex sync. The app is offline-first and should continue to use local SwiftData as the source of truth while later phases add authentication, backend schema, and sync transport.

Current synced candidate models already have stable local `UUID` identifiers plus `createdAt` and `updatedAt` timestamps. The missing Phase 1 pieces are explicit synced entity scope, persistent delete semantics, conflict rules, and test coverage that locks those decisions before backend APIs are designed.

## Synced Entity Scope

The v1 synced scope is:

- `UserSettings`
- `Exercise`
- `WorkoutSession`
- `LoggedExercise`
- `LoggedSet`

The v1 excluded scope is:

- `WorkoutTemplate`: excluded because there is no user-facing template workflow in v1. Existing completed workouts already serve as reusable workout sources.
- `HealthDataLink`: excluded because HealthKit or other external provider sync is deferred.
- `SeedMetadata`: excluded because it is local installation bookkeeping, not user workout data.

## Model Metadata

Each synced model keeps its existing client-generated `UUID` `id` as the stable cross-device identity. Each synced model keeps `createdAt` and `updatedAt`.

Each synced model adds:

- `deletedAt: Date?`
- `isDeleted: Bool`
- `markDeleted(now:)`
- `restoreFromDeletion(now:)`
- `touch(now:)`

`isDeleted` is derived from `deletedAt != nil`. `markDeleted(now:)` sets both `deletedAt` and `updatedAt` to the supplied time. `restoreFromDeletion(now:)` clears `deletedAt` and advances `updatedAt`, allowing explicit recreation or restore behavior later.

## Delete Semantics

Synced entities use tombstones instead of hard deletion when deletion needs to sync. A tombstone preserves the stable local `id` so later sync phases can push the delete to Convex and prevent older remote updates from resurrecting deleted data.

Local UI should filter deleted records out of user-visible active collections. Existing archive behavior remains separate:

- `Exercise.isArchived` remains a product-level hidden-from-library state.
- `deletedAt` means the record is deleted for sync purposes.

For Phase 1, workout graph delete helpers should tombstone parent and child records together:

- Deleting a `WorkoutSession` marks the session, its `LoggedExercise` children, and their `LoggedSet` children deleted.
- Deleting a `LoggedExercise` marks the logged exercise and its sets deleted.
- Deleting a `LoggedSet` marks only that set deleted and reindexes remaining non-deleted sibling sets.

Hard deletes can still exist for non-synced models and test setup cleanup.

## Conflict Behavior

Phase 1 defines, but does not implement backend sync conflict resolution.

For v1:

- The record with the latest `updatedAt` wins.
- A tombstone wins over any older non-deleted update.
- A non-deleted update may only restore a tombstoned record if it has a later `updatedAt` and represents an intentional restore or recreation.
- Equal timestamps are resolved locally by keeping the current local value; later sync engine work can add deterministic tie-breaking if needed.

The model layer should expose a small helper for this policy so Convex sync work can share one local interpretation.

## Persistence and Migration

Adding optional `deletedAt` properties should be covered by persistence tests that prove tombstones save and fetch correctly. Because the app has not shipped publicly yet, Phase 1 can use SwiftData's lightweight migration path without adding a custom versioned migration plan unless tests or local containers show it is required.

The test support should cover:

- New synced entities default to non-deleted.
- `markDeleted(now:)` persists `deletedAt` and advances `updatedAt`.
- `restoreFromDeletion(now:)` clears `deletedAt` and advances `updatedAt`.
- Workout graph tombstoning cascades through sessions, logged exercises, and logged sets.
- User-facing fetch helpers can exclude tombstoned records.
- `WorkoutTemplate` is documented and tested as excluded from the v1 sync scope.

## Non-Goals

This issue does not add:

- Convex schema or functions.
- Clerk authentication.
- Sync engine, outbox, retry state, or network transport.
- User-visible sync UI.
- User-facing workout template workflows.

Those belong to later roadmap phases.
