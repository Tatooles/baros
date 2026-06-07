# Settings And Exercises Sync Design

Issue: [#10 Sync settings and exercises](https://github.com/Tatooles/lifting-log-ios/issues/10)

Date: 2026-06-07

## Decision

Implement the first real iOS sync engine pass for `UserSettings` and `Exercise` only. Use the existing authenticated Convex sync API from issue #8 and the local SwiftData outbox from issue #9. Keep the work mostly headless: prove automatic push, pull, conflict handling, cursor persistence, retry behavior, and local ownership without adding polished sync status or retry UI.

This issue should validate the sync architecture before syncing completed workout graph data.

## Goals

- Push local settings and exercise creates, updates, archives, and deletes to Convex.
- Pull remote settings and exercise changes into SwiftData.
- Avoid duplicate local rows by matching records with stable client UUIDs.
- Preserve offline-first behavior: local edits remain available while sync is unavailable.
- Retry failed sync work safely after app relaunch or later connectivity.
- Persist per-owner change cursors so repeated pulls do not reapply already handled pages.
- Claim existing local-only settings and exercises for the first signed-in Clerk owner.
- Prevent records associated with another owner from syncing under the current owner.
- Add focused unit tests for sync correctness and narrow UI tests for workflow-to-sync trigger wiring.

## Non-Goals

- No completed workout session, logged exercise, or logged set syncing in this issue.
- No in-progress active workout sync.
- No polished user-facing sync status, retry, offline, or error recovery UI. That belongs to issue #12.
- No account-switching merge, transfer, deletion, or separate-local-dataset UX. That belongs to issue #42.
- No new Convex batch sync endpoint unless implementation proves the existing functions are insufficient.
- No analytics, sharing, programs, subscriptions, HealthKit, or other product scope.

## Architecture

Add a scoped iOS sync layer for settings and exercises.

Recommended units:

- `SyncCursorState`: a SwiftData model that stores per-owner cursors for Convex change feeds. It should include `ownerTokenIdentifier`, `userSettingsCursor`, and `exercisesCursor`. If the existing Convex `fetchChanges` request shape requires workout graph cursors, store or provide zero values for those fields without applying workout graph records in this issue.
- `SettingsExerciseSyncCoordinator`: a `@MainActor` service that owns one sync run at a time. It observes or is told about authenticated session state, claims local unowned settings and exercises for first sign-in, pushes pending outbox entries, pulls remote changes, updates cursors, and exposes minimal internal state for diagnostics and tests.
- `ConvexSyncClient`: a thin adapter around `ConvexClientWithAuth<String>` that calls the existing Convex functions: `sync:upsertUserSettings`, `sync:upsertExercise`, `sync:tombstone`, and `sync:fetchChanges`.
- Payload mappers: focused helpers that convert SwiftData models into Convex payload structs and Convex records back into local apply operations.

The app should instantiate the coordinator at the app level, near `LiftingLogApp` or an environment object, so sync is not coupled to a particular screen. Local mutation services remain the source of truth for recording outbox entries.

## Sync Triggers

Run sync automatically when an authenticated Convex session is available:

- after app launch or session restoration,
- after a local settings mutation enqueues outbox work,
- after a local exercise mutation enqueues outbox work,
- after a successful pull page when Convex reports more settings or exercise changes.

Do not add a manual retry button or detailed visible status controls in issue #10. Those controls belong to issue #12.

## Ownership

The coordinator should use the authenticated Clerk/Convex `tokenIdentifier` as the local owner key.

On first sign-in for a local-only install, issue #10 should claim existing unowned `UserSettings`, `Exercise`, and matching settings/exercise outbox entries for the signed-in owner. This is the intended bridge from signed-out local use to signed-in sync.

Once a record or outbox entry is associated with an owner, it must not silently sync under a different owner. If the current owner differs from stored ownership, the coordinator should skip that data and leave broader account-switching behavior for issue #42.

## Push Flow

At the start of a sync run:

1. Require an authenticated owner token identifier. If auth is unavailable, return without changing outbox state.
2. Claim unowned local settings and exercises for the owner if no conflicting ownership exists.
3. Convert abandoned `inFlight` settings/exercise outbox entries for this owner back to `pending` so app relaunch does not strand work.
4. Fetch pending outbox entries for this owner and filter to `.userSettings` and `.exercise`.

For each pending entry:

- Mark it `inFlight` before calling Convex.
- For create or update entries, fetch the local model and call the matching upsert mutation.
- For delete entries, call `sync:tombstone` using the model `deletedAt` timestamp when available, otherwise the entry timestamp.
- Treat Convex `inserted`, `updated`, `tombstoned`, `ignored_stale`, and `missing` tombstone responses as completion for the outbox entry.
- Remove the outbox entry only after the Convex call succeeds.
- If a network or Convex error occurs, mark the current entry `failed` with the error message, save, stop the run, and let a later automatic run retry it.

If a local model is missing for a create, update, or delete entry, convert the entry into a remote tombstone call using the entry's `entityID` and `updatedAt` timestamp. Treat Convex `tombstoned`, `ignored_stale`, and `missing` responses as completion. This avoids resurrecting a local row that no longer exists and keeps retry behavior idempotent.

## Pull Flow

After push succeeds, fetch remote changes with the owner's settings and exercise cursors.

For each received `userSettings` row:

- Match local rows by `clientId` UUID.
- Insert a missing active row.
- Tombstone a local row when the incoming row has `deletedAt`.
- For an existing active row, use `SyncConflictResolver` with local `updatedAt`/`deletedAt` and incoming `updatedAt`/`deletedAt`.
- Apply incoming fields only when the resolver chooses `applyIncoming`.

For each received `exercise` row:

- Match local rows by `clientId` UUID, never by exercise name.
- Insert a missing active row.
- Tombstone a local row when the incoming row has `deletedAt`.
- Apply incoming fields only when the resolver chooses `applyIncoming`.
- Preserve raw taxonomy values from Convex and rely on existing accessors for fallback display.

After a page is fully applied and saved, advance only the cursors for the applied tables. If applying a page fails, do not advance that page's cursor. Continue fetching while Convex reports `hasMore` for settings or exercises.

Remote settings weight-unit changes should update the settings record itself. They should not cascade into completed workout graph sync or enqueue logged-set sync in issue #10. The existing local settings mutation behavior for user-initiated weight-unit changes remains unchanged.

## Conflict Rules

Use the existing timestamp-based `SyncConflictResolver`.

- Equal or older incoming timestamps keep local state.
- Newer incoming active records update local active records.
- Newer incoming tombstones mark local records deleted.
- Local tombstones win over incoming active restores unless restore is explicitly allowed. Issue #10 should not allow incoming restores.
- Stable client UUIDs are the identity boundary. Exercise names, equipment, and seed identifiers must not be used to deduplicate synced rows.

## Error Handling

- Auth unavailable: skip sync and leave pending work untouched.
- Network unavailable or Convex call fails during push: mark the current outbox entry `failed`, preserve later entries, and retry on a future automatic run.
- App relaunch with `inFlight` entries: return relevant entries to `pending` before retry.
- Pull failure before apply: keep cursors unchanged.
- Pull failure after partial apply but before cursor save: allow idempotent reapply on the next run.
- Unknown raw enum values from Convex: preserve raw strings and let local typed accessors display fallbacks.
- Records owned by another owner: skip them and do not mutate ownership.

## UI Behavior

Keep UI changes minimal.

The settings account row may stop saying "Cloud sync is not configured yet" once the coordinator exists, but issue #10 should not introduce detailed states, manual retry controls, or user-facing error recovery. The sync coordinator may expose simple internal state for developer diagnostics and tests.

## Testing

Swift unit tests should cover:

- Payload mapping for `UserSettings`.
- Payload mapping for `Exercise`, including raw taxonomy strings.
- Claiming unowned settings, exercises, and relevant outbox entries for the first signed-in owner.
- Refusing to sync entries owned by a different owner.
- Push success removes outbox entries for settings and exercise create/update/delete.
- Push failure marks entries failed and a later run retries them.
- App relaunch converts abandoned relevant `inFlight` entries back to `pending`.
- Pull creates missing local settings and exercises.
- Pull updates existing rows only when incoming data wins conflict resolution.
- Pull tombstones local rows from remote deletes.
- Pull does not create duplicates when the same remote `clientId` is received again.
- Cursor advancement happens only after a page is applied.
- Remote settings weight-unit changes update settings without enqueueing workout graph sync as part of issue #10.

Narrow UI tests may cover workflow-to-sync trigger wiring:

- Editing settings through `SettingsView` enqueues owned settings sync work and requests a sync run in a test mode.
- Creating, updating, or deleting an exercise through the exercise library/editor enqueues owned exercise sync work and requests a sync run in a test mode.
- Session restoration or a mocked authenticated launch path requests an initial sync run.

UI tests should not validate Convex push/pull correctness. That behavior belongs in unit tests with a fake sync client because it needs deterministic auth, network, and remote responses.

Existing Convex tests can stay mostly unchanged because the backend already covers authenticated upsert, tombstone, access control, stale writes, and change cursors for settings and exercises. Add backend tests only if implementation changes Convex behavior.

Recommended verification commands:

```sh
xcodebuild test -project LiftingLog.xcodeproj -scheme LiftingLog -destination platform=iOS\ Simulator,name=iPhone\ 16,OS=18.6 -only-testing:LiftingLogTests -derivedDataPath /private/tmp/codex-ios-app-derived-data
```

Run Vitest only if Convex files change:

```sh
pnpm test
```

## Implementation Notes

- Keep the coordinator scoped enough that issue #11 can extend it to workout sessions, logged exercises, and logged sets without rewriting settings/exercises sync.
- Prefer dependency injection for `ConvexSyncClient` so unit tests can use a deterministic fake client.
- Avoid storing Convex document IDs locally for this issue; `clientId` and owner token identifier are enough for the existing backend contract.
- Keep timestamps as the conflict source of truth. Send local `createdAt`, `updatedAt`, and `deletedAt` values to Convex as Unix seconds from Swift `Date.timeIntervalSince1970`, matching current model and test usage. Treat Convex `serverUpdatedAt` as an opaque numeric cursor returned by the backend.
- Do not silently upload local data under a second account. If ownership is ambiguous, skip sync and leave issue #42 to define the product behavior.
