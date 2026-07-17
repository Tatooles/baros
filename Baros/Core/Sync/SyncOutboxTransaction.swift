import Foundation
import SwiftData

enum SyncOutboxTransactionError: Error, Equatable {
    case currentOwnerMismatch
    case targetOwnerMismatch
    case unexpectedUnsavedDomainChanges
    case targetIsNotLoggedWorkoutData
}

@MainActor
@Observable
final class SyncOutboxTransaction {
    enum Target {
        case userSettings(UserSettings)
        case exerciseLibraryEntry(Exercise)
        case loggedWorkout(WorkoutSession)
        case loggedExercise(LoggedExercise)
        case loggedSet(LoggedSet)
    }

    @MainActor
    final class Actions {
        private enum Operation {
            case create
            case update
            case delete
        }

        private let modelContext: ModelContext
        private let ownerTokenIdentifier: String
        private let recorder: SyncOutboxRecorder
        private(set) var count = 0

        fileprivate init(
            modelContext: ModelContext,
            ownerTokenIdentifier: String,
            recorder: SyncOutboxRecorder
        ) {
            self.modelContext = modelContext
            self.ownerTokenIdentifier = ownerTokenIdentifier
            self.recorder = recorder
        }

        func update(
            _ target: Target,
            now: Date = .now,
            mutation: (ModelContext) throws -> Void
        ) throws {
            try apply(.update, to: target, now: now, mutation: mutation)
        }

        func create(
            _ target: Target,
            now: Date = .now,
            mutation: (ModelContext) throws -> Void
        ) throws {
            try apply(.create, to: target, now: now, mutation: mutation)
        }

        func delete(
            _ target: Target,
            now: Date = .now,
            mutation: (ModelContext) throws -> Void
        ) throws {
            try apply(.delete, to: target, now: now, mutation: mutation)
        }

        private func apply(
            _ operation: Operation,
            to target: Target,
            now: Date,
            mutation: (ModelContext) throws -> Void
        ) throws {
            try mutation(modelContext)
            try validateOwner(of: target)
            let entityKind = entityKind(of: target)
            let entityID = entityID(of: target)
            switch operation {
            case .create:
                try recorder.recordCreate(
                    entityKind: entityKind,
                    entityID: entityID,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: modelContext,
                    now: now
                )
            case .update:
                try recorder.recordUpdate(
                    entityKind: entityKind,
                    entityID: entityID,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: modelContext,
                    now: now
                )
            case .delete:
                try recorder.recordDelete(
                    entityKind: entityKind,
                    entityID: entityID,
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    context: modelContext,
                    now: now
                )
            }
            count += 1
        }

        private func validateOwner(of target: Target) throws {
            let targetOwnerTokenIdentifier = switch target {
            case let .userSettings(settings):
                settings.syncOwnerTokenIdentifier
            case let .exerciseLibraryEntry(exercise):
                exercise.syncOwnerTokenIdentifier
            case let .loggedWorkout(workout):
                workout.syncOwnerTokenIdentifier
            case let .loggedExercise(loggedExercise):
                loggedExercise.session?.syncOwnerTokenIdentifier
            case let .loggedSet(loggedSet):
                loggedSet.loggedExercise?.session?.syncOwnerTokenIdentifier
            }

            guard targetOwnerTokenIdentifier == ownerTokenIdentifier else {
                throw SyncOutboxTransactionError.targetOwnerMismatch
            }

            switch target {
            case .userSettings, .exerciseLibraryEntry:
                break
            case let .loggedWorkout(workout):
                guard workout.status == .completed else {
                    throw SyncOutboxTransactionError.targetIsNotLoggedWorkoutData
                }
            case let .loggedExercise(loggedExercise):
                guard loggedExercise.session?.status == .completed else {
                    throw SyncOutboxTransactionError.targetIsNotLoggedWorkoutData
                }
            case let .loggedSet(loggedSet):
                guard loggedSet.loggedExercise?.session?.status == .completed else {
                    throw SyncOutboxTransactionError.targetIsNotLoggedWorkoutData
                }
            }
        }

        private func entityKind(of target: Target) -> SyncEntityKind {
            switch target {
            case .userSettings:
                .userSettings
            case .exerciseLibraryEntry:
                .exercise
            case .loggedWorkout:
                .workoutSession
            case .loggedExercise:
                .loggedExercise
            case .loggedSet:
                .loggedSet
            }
        }

        private func entityID(of target: Target) -> UUID {
            switch target {
            case let .userSettings(settings):
                settings.id
            case let .exerciseLibraryEntry(exercise):
                exercise.id
            case let .loggedWorkout(workout):
                workout.id
            case let .loggedExercise(loggedExercise):
                loggedExercise.id
            case let .loggedSet(loggedSet):
                loggedSet.id
            }
        }
    }

    var currentOwnerTokenIdentifier: String? {
        syncScheduler.currentOwnerTokenIdentifier
    }

    private let modelContext: ModelContext
    private let syncScheduler: SyncScheduler
    private let recorder = SyncOutboxRecorder()
    private let save: @MainActor (ModelContext) throws -> Void

    init(
        modelContext: ModelContext,
        syncScheduler: SyncScheduler,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.syncScheduler = syncScheduler
        self.save = save
    }

    func perform(
        ownerTokenIdentifier: String,
        operation: (Actions) throws -> Void
    ) throws {
        guard currentOwnerTokenIdentifier == ownerTokenIdentifier else {
            throw SyncOutboxTransactionError.currentOwnerMismatch
        }

        let outboxBookkeeping = OutboxBookkeepingSnapshot.capture(from: modelContext)
        guard !hasUnsavedDomainChanges else {
            modelContext.rollback()
            outboxBookkeeping.restore(in: modelContext)
            throw SyncOutboxTransactionError.unexpectedUnsavedDomainChanges
        }

        let actions = Actions(
            modelContext: modelContext,
            ownerTokenIdentifier: ownerTokenIdentifier,
            recorder: recorder
        )
        do {
            try operation(actions)
            guard actions.count > 0 else {
                guard !hasUnsavedDomainChanges else {
                    throw SyncOutboxTransactionError.unexpectedUnsavedDomainChanges
                }
                return
            }
            try save(modelContext)
        } catch {
            modelContext.rollback()
            outboxBookkeeping.restore(in: modelContext)
            throw error
        }

        syncScheduler.requestSync()
    }

    private var hasUnsavedDomainChanges: Bool {
        guard modelContext.hasChanges else { return false }

        for model in modelContext.insertedModelsArray where !(model is SyncOutboxEntry) {
            return true
        }
        for model in modelContext.changedModelsArray where !(model is SyncOutboxEntry) {
            return true
        }
        for model in modelContext.deletedModelsArray where !(model is SyncOutboxEntry) {
            return true
        }
        return false
    }
}

@MainActor
private struct OutboxBookkeepingSnapshot {
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
                entry.statusRaw = statusRaw + "#restoring"
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
