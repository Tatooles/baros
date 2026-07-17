---
status: accepted
---

# Centralize offline-first mutations

Every owner-scoped, user-originated syncable mutation must run through one internal transaction module. Each transaction explicitly declares its owner, which must match the Current Owner before changes begin; cloud authorization is not required for local access. Domain modules explicitly name each create, update, or delete action because they own the rules that determine the correct action; the transaction module does not infer those rules. Each named action wraps the corresponding model change and records its outbox intent, preventing the change and intent from drifting apart. One transaction may contain several named actions, but it saves once, requests sync once, and rolls back every action if any part fails. A transaction with no named actions returns successfully without saving or requesting sync. The module starts with a clean SwiftData context and requests sync only after a successful save. If the context is unexpectedly dirty before the operation starts, the module rolls it back to the last successful save and returns a recoverable error; user input remains in a separate draft so the user can retry.

Domain modules retain their exercise, settings, and workout rules. Active Workouts remain local and outside this transaction path until they become Logged Workouts. This trades caller flexibility for one enforceable offline-first guarantee and one test surface as the app grows.

Unclaimed Local Data is saved without outbox entries because it has no owner destination. When the ownership flow assigns eligible Unclaimed Local Data to the Current Owner, the existing bootstrap process scans the SwiftData records and creates owner-scoped outbox work. Owner-scoped changes always create outbox entries even when cloud synchronization is paused or the device is offline.

This change does not introduce a second shared transaction module for Unclaimed Local Data. Domain modules continue to save and roll back that simpler local-only path directly; it can be deepened separately if concrete friction emerges.

As a narrow safety guard, the transaction module rejects a workout, logged exercise, or logged set that is not part of a Logged Workout. It does not own workout completion rules or status transitions; those remain in the workout domain module.

The `SyncOutboxTransaction` module exposes one throwing `perform` seam that returns `Void`. Returning normally means the owner-scoped transaction succeeded or had no actions; it does not mean cloud synchronization completed. Its transaction value is available only inside that operation and provides explicit `create`, `update`, and `delete` actions that wrap domain changes. SwiftData saving, rollback, outbox recording, ownership validation, and post-save sync remain hidden behind the seam. `SyncScheduler` is a required dependency, and every successful non-empty transaction requests sync exactly once after saving; the scheduler decides whether synchronization can run immediately. A paused scheduler keeps the durable outbox work queued while the Current Owner remains able to edit local data. Tests exercise the same interface with the existing in-memory SwiftData container rather than introducing an adapter protocol.

The interface uses a closed target list named by domain role: `userSettings`, `exerciseLibraryEntry`, `loggedWorkout`, `loggedExercise`, and `loggedSet`. The module owns the exhaustive mapping from those targets to the existing SwiftData model types, outbox entity kinds, identifiers, ownership, and sync eligibility. This keeps outbox knowledge out of the persisted models and makes support for each new synced model an explicit change in one place.

The app creates one `SyncOutboxTransaction` with its main `ModelContext` and `SyncScheduler`, then injects it into the domain modules that perform synced mutations. It is app-scoped rather than a global singleton. Tests construct independent instances with an in-memory context and test scheduler.

The transaction interface is the primary test surface for persistence and outbox guarantees. Its tests cover every target and action, ownership, multi-action rollback, dirty-context recovery, no-op behavior, scheduling, and active-draft rejection. Domain-module tests continue to cover exercise, settings, and workout rules without duplicating the transaction sequence.

All existing user-facing syncable mutation paths migrate to this module before the change merges. Implementation proceeds in stages—transaction module and contract tests, settings and exercise-library mutations, logged-workout completion and history mutations, then removal of duplicated save, rollback, outbox, and scheduling code—without leaving competing transaction patterns in the merged codebase.

The seam covers user-originated domain changes only. Applying downloaded changes, maintaining or retrying the outbox, seeding and bootstrap, and account-deletion recovery remain outside the module because they manage replication itself and must not enqueue their own work for upload.

The transaction module never claims Unclaimed Local Data automatically. An ownership or domain workflow may explicitly assign it to the Current Owner when existing rules allow; the transaction validates that each target's final owner matches the declared owner before saving. Data that remains unclaimed or belongs to another owner causes the operation to roll back.

When an operation fails, the module rolls back and rethrows the original domain or persistence error. It introduces its own errors only for transaction rules such as an unexpected dirty context or ownership mismatch, preserving the real cause for logs and tests while allowing the UI to present a simpler message.
