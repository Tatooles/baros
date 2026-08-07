import Foundation
import SwiftData

/// Preserves the unsaved `SyncOutboxEntry` bookkeeping that a suspended sync
/// leaves in the shared `ModelContext`.
///
/// `pushPendingEntries` marks an entry in-flight, then suspends at its network
/// `await` with that change still unsaved. Any `rollback()` on the shared
/// context during that window reverts the entry to `pending`, so a remote
/// mutation that already succeeded is pushed a second time. Every rollback
/// owner therefore captures this bookkeeping and restores it afterwards.

struct OutboxBookkeepingSnapshot {
    private enum Change {
        case inserted
        case changed
        case deleted
    }

    private struct EntrySnapshot {
        let entry: SyncOutboxEntry
        let change: Change
        let entityKindRaw: String
        let entityID: UUID
        let operationRaw: String
        let statusRaw: String
        let ownerTokenIdentifier: String?
        let createdAt: Date
        let updatedAt: Date
        let lastAttemptAt: Date?
        let attemptCount: Int
        let lastErrorMessage: String?

        init(entry: SyncOutboxEntry, change: Change) {
            self.entry = entry
            self.change = change
            entityKindRaw = entry.entityKindRaw
            entityID = entry.entityID
            operationRaw = entry.operationRaw
            statusRaw = entry.statusRaw
            ownerTokenIdentifier = entry.ownerTokenIdentifier
            createdAt = entry.createdAt
            updatedAt = entry.updatedAt
            lastAttemptAt = entry.lastAttemptAt
            attemptCount = entry.attemptCount
            lastErrorMessage = entry.lastErrorMessage
        }

        func restore(in modelContext: ModelContext) {
            if case .changed = change {
                // `rollback()` reverts the entry to its last saved values and clears its dirty
                // flag. Re-assigning a captured value that happens to match the saved one is then
                // a no-op, so the entry would not be marked changed and the next save would drop
                // the in-flight bookkeeping this snapshot exists to preserve. Write a value that
                // cannot match first to force the entry dirty. `updatedAt` is used rather than a
                // raw enum field so no reader can ever observe an unparseable status.
                entry.updatedAt = .distantPast
            }
            entry.entityKindRaw = entityKindRaw
            entry.entityID = entityID
            entry.operationRaw = operationRaw
            entry.statusRaw = statusRaw
            entry.ownerTokenIdentifier = ownerTokenIdentifier
            entry.createdAt = createdAt
            entry.updatedAt = updatedAt
            entry.lastAttemptAt = lastAttemptAt
            entry.attemptCount = attemptCount
            entry.lastErrorMessage = lastErrorMessage

            switch change {
            case .inserted:
                modelContext.insert(entry)
            case .changed:
                break
            case .deleted:
                modelContext.delete(entry)
            }
        }
    }

    private let entries: [EntrySnapshot]

    static func capture(from modelContext: ModelContext) -> Self {
        let insertedEntries = modelContext.insertedModelsArray.compactMap { $0 as? SyncOutboxEntry }
        let insertedObjects = Set(insertedEntries.map(ObjectIdentifier.init))
        let changedEntries = modelContext.changedModelsArray.compactMap { $0 as? SyncOutboxEntry }
            .filter { !insertedObjects.contains(ObjectIdentifier($0)) }
        let deletedEntries = modelContext.deletedModelsArray.compactMap { $0 as? SyncOutboxEntry }
            .filter { !insertedObjects.contains(ObjectIdentifier($0)) }

        return Self(entries:
            insertedEntries.map { EntrySnapshot(entry: $0, change: .inserted) }
                + changedEntries.map { EntrySnapshot(entry: $0, change: .changed) }
                + deletedEntries.map { EntrySnapshot(entry: $0, change: .deleted) }
        )
    }

    func restore(in modelContext: ModelContext) {
        for entry in entries {
            entry.restore(in: modelContext)
        }
    }
}

extension OutboxBookkeepingSnapshot {
    /// Rolls back while keeping whatever outbox bookkeeping is already in the
    /// context. Safe for the paths that never record intents of their own — the
    /// Active Workout and Unclaimed Local Data saves — where every outbox change
    /// present necessarily belongs to a concurrent sync.
    ///
    /// `SyncOutboxTransaction` cannot use this: it captures *before* running its
    /// operation so that the entries it records itself are correctly discarded.
    static func rollbackPreservingBookkeeping(in context: ModelContext) {
        let snapshot = capture(from: context)
        context.rollback()
        snapshot.restore(in: context)
    }
}
