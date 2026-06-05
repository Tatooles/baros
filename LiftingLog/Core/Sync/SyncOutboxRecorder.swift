import Foundation
import SwiftData

struct SyncOutboxRecorder {
    func recordCreate(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date
    ) throws {
        guard entityKind.isV1Synced else { return }

        if let entry = try activeEntry(
            entityKind: entityKind,
            entityID: entityID,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ) {
            entry.operation = .create
            entry.refreshPending(now: now)
            return
        }

        context.insert(
            SyncOutboxEntry(
                entityKind: entityKind,
                entityID: entityID,
                operation: .create,
                ownerTokenIdentifier: ownerTokenIdentifier,
                now: now
            )
        )
    }

    func recordUpdate(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date
    ) throws {
        guard entityKind.isV1Synced else { return }

        if let entry = try activeEntry(
            entityKind: entityKind,
            entityID: entityID,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ) {
            if entry.operation != .delete {
                entry.operation = entry.operation == .create ? .create : .update
            }
            entry.refreshPending(now: now)
            return
        }

        context.insert(
            SyncOutboxEntry(
                entityKind: entityKind,
                entityID: entityID,
                operation: .update,
                ownerTokenIdentifier: ownerTokenIdentifier,
                now: now
            )
        )
    }

    func recordDelete(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date
    ) throws {
        guard entityKind.isV1Synced else { return }

        if let entry = try activeEntry(
            entityKind: entityKind,
            entityID: entityID,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ) {
            if entry.operation == .create && !entry.hasBeenAttempted {
                context.delete(entry)
                return
            }

            entry.operation = .delete
            entry.refreshPending(now: now)
            return
        }

        context.insert(
            SyncOutboxEntry(
                entityKind: entityKind,
                entityID: entityID,
                operation: .delete,
                ownerTokenIdentifier: ownerTokenIdentifier,
                now: now
            )
        )
    }

    func markInFlight(_ entry: SyncOutboxEntry, now: Date) {
        entry.attemptCount += 1
        entry.lastAttemptAt = now
        entry.lastErrorMessage = nil
        entry.updatedAt = now
        entry.status = .inFlight
    }

    func markFailed(_ entry: SyncOutboxEntry, message: String, now: Date) {
        entry.status = .failed
        entry.lastErrorMessage = message
        entry.updatedAt = now
    }

    func markPendingForRetry(_ entry: SyncOutboxEntry, now: Date) {
        entry.status = .pending
        entry.lastErrorMessage = nil
        entry.updatedAt = now
    }

    func removeCompleted(_ entry: SyncOutboxEntry, context: ModelContext) {
        context.delete(entry)
    }

    func pendingEntries(context: ModelContext) throws -> [SyncOutboxEntry] {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .filter { entry in
                guard let entityKind = entry.entityKind, entityKind.isV1Synced else {
                    return false
                }
                guard entry.operation != nil else {
                    return false
                }

                switch entry.status {
                case .pending, .inFlight, .failed:
                    return true
                case .completed, nil:
                    return false
                }
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.updatedAt < rhs.updatedAt
            }
    }

    private func activeEntry(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) throws -> SyncOutboxEntry? {
        try context.fetch(FetchDescriptor<SyncOutboxEntry>())
            .filter { entry in
                entry.entityKind == entityKind
                    && entry.entityID == entityID
                    && entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && entry.isActive
                    && entry.operation != nil
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.updatedAt < rhs.updatedAt
                }

                return lhs.createdAt < rhs.createdAt
            }
            .first
    }
}
