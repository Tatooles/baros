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
        private let ownerTokenIdentifier: String?
        private let recorder: SyncOutboxRecorder
        private(set) var count = 0

        fileprivate init(
            modelContext: ModelContext,
            ownerTokenIdentifier: String?,
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
            try preserveLegacyWorkoutDeclineIfThisCreatesFreshIntent(target: target)
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

        /// Older cursor rows did not persist which ownerless workouts the user declined. If the
        /// user edits one of those workouts before the first post-upgrade sync, the new ownerless
        /// intent must not be mistaken for old evidence that upload had already been approved.
        /// Record that workout in the existing declined list before creating its first intent.
        private func preserveLegacyWorkoutDeclineIfThisCreatesFreshIntent(target: Target) throws {
            guard ownerTokenIdentifier == nil,
                  let session = workoutSession(for: target),
                  session.status == .completed,
                  !(try hasActiveOwnerlessIntent(in: session)) else {
                return
            }

            for state in try modelContext.fetch(FetchDescriptor<SyncCursorState>())
            where state.hasBootstrappedWorkoutGraph && !state.hasEvaluatedOwnerlessWorkoutAdoption {
                if !state.declinedOwnerlessWorkoutIDs.contains(session.id) {
                    state.declinedOwnerlessWorkoutIDs.append(session.id)
                }
            }
        }

        private func workoutSession(for target: Target) -> WorkoutSession? {
            switch target {
            case .userSettings, .exerciseLibraryEntry:
                nil
            case let .loggedWorkout(workout):
                workout
            case let .loggedExercise(loggedExercise):
                loggedExercise.session
            case let .loggedSet(loggedSet):
                loggedSet.loggedExercise?.session
            }
        }

        private func hasActiveOwnerlessIntent(in session: WorkoutSession) throws -> Bool {
            let completedStatus = SyncOutboxStatus.completed.rawValue
            let entries = try modelContext.fetch(FetchDescriptor<SyncOutboxEntry>(
                predicate: #Predicate { entry in
                    entry.ownerTokenIdentifier == nil
                        && entry.statusRaw != completedStatus
                        && entry.operationRaw != ""
                }
            ))
            let loggedExerciseIDs = Set(session.loggedExercises.map(\.id))
            let loggedSetIDs = Set(session.loggedExercises.flatMap { $0.sets.map(\.id) })
            return entries.contains { entry in
                switch entry.entityKind {
                case .workoutSession:
                    entry.entityID == session.id
                case .loggedExercise:
                    loggedExerciseIDs.contains(entry.entityID)
                case .loggedSet:
                    loggedSetIDs.contains(entry.entityID)
                default:
                    false
                }
            }
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
        try run(ownerTokenIdentifier: ownerTokenIdentifier, operation: operation)
    }

    /// The Unclaimed Local Data counterpart. Same save, rollback, and scheduling
    /// mechanics; two rules differ.
    ///
    /// There is no Current Owner comparison, because unclaimed data stays editable
    /// no matter who is signed in — deleting local history from another account must
    /// not be rejected. Every target must still be ownerless, which `Actions`
    /// enforces by comparing each one against the declared `nil` owner.
    ///
    /// The intents it records are ownerless. They are what carries unclaimed data to
    /// the cloud once an owner claims it, and they double as the durable record that
    /// the user edited a row locally: sync preparation reads them to claim rows after
    /// the one-time bootstrap, and seed merging reads them to tell an edited
    /// duplicate apart from a freshly re-seeded default.
    func performUnclaimed(operation: (Actions) throws -> Void) throws {
        try run(ownerTokenIdentifier: nil, operation: operation)
    }

    private func run(
        ownerTokenIdentifier: String?,
        operation: (Actions) throws -> Void
    ) throws {
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
