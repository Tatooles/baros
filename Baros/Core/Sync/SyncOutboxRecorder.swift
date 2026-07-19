import Foundation
import SwiftData

@MainActor
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
            if entry.operation != .delete {
                entry.operation = .create
            }
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
            entry.createdAt = now
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
        guard entry.status == .inFlight else {
            return
        }

        context.delete(entry)
    }

    func bootstrapV1SyncableRecords(
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date
    ) throws {
        for settings in try context.fetch(FetchDescriptor<UserSettings>()) {
            try recordBootstrapEntry(
                entityKind: .userSettings,
                entityID: settings.id,
                isDeleted: settings.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }

        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            try recordBootstrapEntry(
                entityKind: .exercise,
                entityID: exercise.id,
                isDeleted: exercise.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }

        for session in try context.fetch(FetchDescriptor<WorkoutSession>()) where session.status != .active {
            try recordBootstrapEntry(
                entityKind: .workoutSession,
                entityID: session.id,
                isDeleted: session.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )

            for loggedExercise in session.loggedExercises {
                try recordBootstrapEntry(
                    entityKind: .loggedExercise,
                    entityID: loggedExercise.id,
                    isDeleted: loggedExercise.isDeleted,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )

                for set in loggedExercise.sets {
                    try recordBootstrapEntry(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        isDeleted: set.isDeleted,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context,
                        now: now
                    )
                }
            }
        }
    }

    func enqueueOwnedV1SyncableRecords(
        ownerTokenIdentifier: String,
        context: ModelContext,
        now: Date
    ) throws {
        for settings in try context.fetch(FetchDescriptor<UserSettings>())
            where settings.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            try recordBootstrapEntry(
                entityKind: .userSettings,
                entityID: settings.id,
                isDeleted: settings.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }

        for exercise in try context.fetch(FetchDescriptor<Exercise>())
            where exercise.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            try recordBootstrapEntry(
                entityKind: .exercise,
                entityID: exercise.id,
                isDeleted: exercise.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }

        for session in try context.fetch(FetchDescriptor<WorkoutSession>())
            where session.status != .active
                && session.syncOwnerTokenIdentifier == ownerTokenIdentifier {
            try recordBootstrapEntry(
                entityKind: .workoutSession,
                entityID: session.id,
                isDeleted: session.isDeleted,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )

            for loggedExercise in session.loggedExercises {
                try recordBootstrapEntry(
                    entityKind: .loggedExercise,
                    entityID: loggedExercise.id,
                    isDeleted: loggedExercise.isDeleted,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: context,
                    now: now
                )

                for set in loggedExercise.sets {
                    try recordBootstrapEntry(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        isDeleted: set.isDeleted,
                        ownerTokenIdentifier: ownerTokenIdentifier,
                        context: context,
                        now: now
                    )
                }
            }
        }
    }

    func pendingEntries(context: ModelContext) throws -> [SyncOutboxEntry] {
        let pendingStatus = SyncOutboxStatus.pending.rawValue
        return try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.statusRaw == pendingStatus
            }
        ))
            .filter { entry in
                guard let entityKind = entry.entityKind, entityKind.isV1Synced else {
                    return false
                }
                guard entry.operation != nil else {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.createdAt < rhs.createdAt
                }

                return lhs.updatedAt < rhs.updatedAt
            }
    }

    func pendingEntries(
        ownerTokenIdentifier: String,
        context: ModelContext
    ) throws -> [SyncOutboxEntry] {
        let pendingStatus = SyncOutboxStatus.pending.rawValue
        let descriptor = FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.statusRaw == pendingStatus
                    && entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && entry.operationRaw != ""
            },
            sortBy: [
                SortDescriptor(\.updatedAt),
                SortDescriptor(\.createdAt),
            ]
        )

        return try context.fetch(descriptor)
            .filter { entry in
                guard let entityKind = entry.entityKind, entityKind.isV1Synced else {
                    return false
                }
                return entry.operation != nil
            }
    }

    private func activeEntry(
        entityKind: SyncEntityKind,
        entityID: UUID,
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) throws -> SyncOutboxEntry? {
        let entityKindRaw = entityKind.rawValue
        let completedStatus = SyncOutboxStatus.completed.rawValue
        return try context.fetch(FetchDescriptor<SyncOutboxEntry>(
            predicate: #Predicate { entry in
                entry.entityKindRaw == entityKindRaw
                    && entry.entityID == entityID
                    && entry.ownerTokenIdentifier == ownerTokenIdentifier
                    && entry.statusRaw != completedStatus
                    && entry.operationRaw != ""
            }
        ))
            .filter { entry in
                entry.operation != nil
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.updatedAt < rhs.updatedAt
                }

                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    private func recordBootstrapEntry(
        entityKind: SyncEntityKind,
        entityID: UUID,
        isDeleted: Bool,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        now: Date
    ) throws {
        guard try activeEntry(
            entityKind: entityKind,
            entityID: entityID,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ) == nil else {
            return
        }

        if isDeleted {
            try recordDelete(
                entityKind: entityKind,
                entityID: entityID,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        } else {
            try recordCreate(
                entityKind: entityKind,
                entityID: entityID,
                ownerTokenIdentifier: ownerTokenIdentifier,
                context: context,
                now: now
            )
        }
    }
}
