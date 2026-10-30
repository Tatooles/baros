import Foundation
import Observation
import SwiftData

enum ActiveWorkoutEngineError: LocalizedError, Equatable {
    case accountTransitionInProgress
    case multipleActiveWorkouts
    case anotherOwnerHasActiveWorkout
    case invalidExerciseReorder
    case invalidExerciseSwap
    case invalidSupersetChange
    case pastWorkoutUnavailable
    case templateUnavailable

    var errorDescription: String? {
        switch self {
        case .accountTransitionInProgress:
            return "Close account management before starting a workout."
        case .multipleActiveWorkouts:
            return "More than one unfinished workout is saved on this iPhone. Resolve them in Settings before starting another."
        case .anotherOwnerHasActiveWorkout:
            return "An active workout from another account is saved on this iPhone. Resolve it before starting another workout."
        case .invalidExerciseReorder:
            return "Workout exercises changed. Review the current order and try again."
        case .invalidExerciseSwap:
            return "That exercise can no longer be swapped. Review the workout and try again."
        case .invalidSupersetChange:
            return "Workout exercises changed. Review the superset and try again."
        case .pastWorkoutUnavailable:
            return "That past workout is no longer available. Choose another workout and try again."
        case .templateUnavailable:
            return "That template is no longer available. Choose another template and try again."
        }
    }
}

@Observable
@MainActor
final class ActiveWorkoutEngine {
    @ObservationIgnored private let reportSetSaveFailure: (ActiveWorkoutSetSaveFailure) -> Void

    @ObservationIgnored let restTimer: RestTimerCoordinator
    @ObservationIgnored var restSettingsOwnerTokenIdentifier: String?

    init(restTimer: RestTimerCoordinator = RestTimerCoordinator(), reportSetSaveFailure: @escaping (ActiveWorkoutSetSaveFailure) -> Void = { SentrySetSaveFailureReporter.capture($0) }) {
        self.restTimer = restTimer
        self.reportSetSaveFailure = reportSetSaveFailure
    }

    var activeSessionID: UUID?
    var isStartingWorkout = false
    var isAccountTransitionInProgress = false
    var isAccountManagementPresented = false
    var lastErrorMessage: String?
    private var pendingSetSave: PendingSetSave?
    #if DEBUG
    @ObservationIgnored private var injectedSetSaveFailureCount = 0
    @ObservationIgnored private var injectedAddExerciseSaveFailureCount = 0
    @ObservationIgnored private var injectedReorderExercisesSaveFailureCount = 0
    #endif
    var hasPendingSetSave: Bool { pendingSetSave != nil }
    /// The Previous column's values, keyed by logged exercise. A linked round
    /// fills each partner's empty fields from them, as that partner's own check would.
    @ObservationIgnored var previousSetsByLoggedExerciseID: [UUID: [PreviousSetPerformance]] = [:]
    var pendingSetSaveID: UUID? { pendingSetSave?.id }

    func loadActiveSession(ownerTokenIdentifier: String? = nil, context: ModelContext) {
        do {
            let session = try currentActiveSession(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
            activeSessionID = session?.id
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func startBlankWorkout(
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws -> WorkoutSession {
        try requireWorkoutStartAllowed(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        if let active = try currentActiveSession(ownerTokenIdentifier: ownerTokenIdentifier, context: context) {
            activeSessionID = active.id
            return active
        }

        isStartingWorkout = true
        defer { isStartingWorkout = false }

        let session = WorkoutSession(
            title: WorkoutSession.defaultTitle,
            startedAt: now,
            status: .active,
            source: .blank,
            createdAt: now,
            updatedAt: now,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(session)
        try context.save()
        activeSessionID = session.id
        return session
    }

    @discardableResult
    func startWorkout(
        fromPast pastSession: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws -> WorkoutSession {
        guard try isVisiblePastWorkout(
            pastSession,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        ) else {
            throw ActiveWorkoutEngineError.pastWorkoutUnavailable
        }

        try requireWorkoutStartAllowed(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        if let active = try currentActiveSession(ownerTokenIdentifier: ownerTokenIdentifier, context: context) {
            activeSessionID = active.id
            return active
        }

        isStartingWorkout = true
        defer { isStartingWorkout = false }

        let session = WorkoutSession(
            title: pastSession.title,
            startedAt: now,
            status: .active,
            source: .pastWorkout,
            sourceSessionID: pastSession.id,
            createdAt: now,
            updatedAt: now,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(session)

        let pastLoggedExercises = pastSession.sortedLoggedExercises
        let copiedGroupIDs = SupersetGrouping.copied(pastLoggedExercises.map(\.supersetGroupID))
        for (pastLoggedExercise, supersetGroupID) in zip(pastLoggedExercises, copiedGroupIDs) {
            let resolvedEquipmentRaw = pastLoggedExercise.resolvedSnapshotEquipmentRaw
            let resolvedPrimaryMuscleGroupRaw = pastLoggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw
            let loggedExercise = LoggedExercise(
                orderIndex: pastLoggedExercise.orderIndex,
                exercise: pastLoggedExercise.exercise,
                exerciseSnapshotName: pastLoggedExercise.exerciseSnapshotName,
                exerciseSnapshotEquipmentRaw: resolvedEquipmentRaw,
                exerciseSnapshotPrimaryMuscleGroupRaw: resolvedPrimaryMuscleGroupRaw,
                sourceLoggedExerciseID: pastLoggedExercise.id,
                supersetGroupID: supersetGroupID,
                createdAt: now,
                updatedAt: now
            )
            loggedExercise.hasSnapshotMetadata =
                resolvedEquipmentRaw != nil && resolvedPrimaryMuscleGroupRaw != nil
            loggedExercise.session = session
            context.insert(loggedExercise)

            for pastSet in pastLoggedExercise.sortedSets {
                let set = LoggedSet(
                    orderIndex: pastSet.orderIndex,
                    kind: pastSet.kind,
                    isCompleted: false,
                    createdAt: now,
                    updatedAt: now,
                    sourceLoggedSetID: pastSet.id
                )
                set.loggedExercise = loggedExercise
                context.insert(set)
                loggedExercise.sets.append(set)
            }

            session.loggedExercises.append(loggedExercise)
        }

        try context.save()
        activeSessionID = session.id
        return session
    }

    /// Starts with the template's exercises in order. Each gets set rows the
    /// way adding it would; an entry whose exercise is gone keeps its name.
    @discardableResult
    func startWorkout(
        fromTemplate template: WorkoutTemplate,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws -> WorkoutSession {
        guard !template.isDeleted, template.isVisible(to: ownerTokenIdentifier) else {
            throw ActiveWorkoutEngineError.templateUnavailable
        }

        try requireWorkoutStartAllowed(ownerTokenIdentifier: ownerTokenIdentifier, context: context)
        if let active = try currentActiveSession(ownerTokenIdentifier: ownerTokenIdentifier, context: context) {
            activeSessionID = active.id
            return active
        }

        isStartingWorkout = true
        defer { isStartingWorkout = false }

        let history = try context.fetch(FetchDescriptor<WorkoutSession>())
        let exercisesByID = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>())
                .filter { $0.isVisible(to: ownerTokenIdentifier) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let session = WorkoutSession(
            title: template.name,
            startedAt: now,
            status: .active,
            source: .template,
            createdAt: now,
            updatedAt: now,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(session)

        let entries = template.entries
        let copiedGroupIDs = SupersetGrouping.copied(entries.map(\.supersetGroupID))
        for (index, (entry, supersetGroupID)) in zip(entries, copiedGroupIDs).enumerated() {
            let exercise = entry.exerciseID.flatMap { exercisesByID[$0] }
            let loggedExercise = LoggedExercise(
                orderIndex: index,
                exercise: exercise,
                exerciseSnapshotName: exercise?.name ?? entry.exerciseSnapshotName,
                exerciseSnapshotEquipmentRaw: exercise?.equipmentRaw ?? entry.exerciseSnapshotEquipmentRaw,
                exerciseSnapshotPrimaryMuscleGroupRaw: exercise?.primaryMuscleGroupRaw
                    ?? entry.exerciseSnapshotPrimaryMuscleGroupRaw,
                supersetGroupID: supersetGroupID,
                createdAt: now,
                updatedAt: now
            )
            loggedExercise.session = session
            context.insert(loggedExercise)

            let kinds = exercise.map {
                initialSetKinds(for: $0, ownerTokenIdentifier: ownerTokenIdentifier, sessions: history)
            } ?? [.working]
            for (setIndex, kind) in kinds.enumerated() {
                let set = LoggedSet(orderIndex: setIndex, kind: kind, createdAt: now, updatedAt: now)
                set.loggedExercise = loggedExercise
                context.insert(set)
                loggedExercise.sets.append(set)
            }

            session.loggedExercises.append(loggedExercise)
        }

        try context.save()
        activeSessionID = session.id
        return session
    }

    @discardableResult
    func addExercise(
        _ exercise: Exercise,
        to session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> LoggedExercise {
        try insertExercises(
            [exercise], to: session, ownerTokenIdentifier: ownerTokenIdentifier,
            context: context, save: save
        )[0]
    }

    /// Appends a picker selection in tap order, saving the whole group together.
    @discardableResult
    func addExercises(
        _ exercises: [Exercise],
        to session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> [LoggedExercise] {
        var seen = Set(session.sortedLoggedExercises.compactMap { $0.exercise?.id })
        let additions = exercises.filter { seen.insert($0.id).inserted }
        guard !additions.isEmpty else { return [] }
        return try insertExercises(
            additions, to: session, ownerTokenIdentifier: ownerTokenIdentifier,
            context: context, save: save
        )
    }

    private func insertExercises(
        _ exercises: [Exercise],
        to session: WorkoutSession,
        ownerTokenIdentifier: String?,
        context: ModelContext,
        save: (ModelContext) throws -> Void,
        plannedSetKinds: [[SetKind]]? = nil
    ) throws -> [LoggedExercise] {
        guard !exercises.isEmpty else { return [] }
        let setKinds: [[SetKind]]
        if let plannedSetKinds {
            setKinds = plannedSetKinds
        } else {
            // Resolve history before inserting anything, so a fetch failure leaves no partial group.
            let history = try context.fetch(FetchDescriptor<WorkoutSession>())
            setKinds = exercises.map {
                initialSetKinds(for: $0, ownerTokenIdentifier: ownerTokenIdentifier, sessions: history)
            }
        }
        let originalSessionUpdatedAt = session.updatedAt
        let nextIndex = (session.sortedLoggedExercises.map(\.orderIndex).max() ?? -1) + 1
        var additions: [LoggedExercise] = []
        for (offset, exercise) in exercises.enumerated() {
            let loggedExercise = LoggedExercise(orderIndex: nextIndex + offset, exercise: exercise)
            loggedExercise.session = session
            context.insert(loggedExercise)
            for (index, kind) in setKinds[offset].enumerated() {
                let set = LoggedSet(orderIndex: index, kind: kind)
                set.loggedExercise = loggedExercise
                context.insert(set)
                loggedExercise.sets.append(set)
            }
            session.loggedExercises.append(loggedExercise)
            additions.append(loggedExercise)
        }
        session.touch()
        do {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--uitest-in-memory-store"),
               arguments.contains("--uitest-fail-add-exercise-save-once"),
               injectedAddExerciseSaveFailureCount == 0 {
                injectedAddExerciseSaveFailureCount += 1
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            try save(context)
            return additions
        } catch {
            let addedIDs = Set(additions.map(\.id))
            session.loggedExercises.removeAll { addedIDs.contains($0.id) }
            for loggedExercise in additions {
                for set in loggedExercise.sets {
                    context.delete(set)
                }
                context.delete(loggedExercise)
            }
            session.updatedAt = originalSessionUpdatedAt
            throw error
        }
    }

    func removeLoggedExercise(_ loggedExercise: LoggedExercise, context: ModelContext, now: Date = .now) throws {
        let session = loggedExercise.session
        loggedExercise.markDeleted(now: now)
        for set in loggedExercise.sets {
            set.markDeleted(now: now)
        }
        if let session {
            reindexLoggedExercises(for: session, now: now)
            normalizeSupersets(session.sortedLoggedExercises, now: now)
            session.touch(now: now)
        }
        try context.save()
        for set in loggedExercise.sets { restTimer.cancel(ifStartedBy: set.id) }
    }

    @discardableResult
    func swapLoggedExercise(
        _ loggedExercise: LoggedExercise,
        with exercise: Exercise,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> LoggedExercise {
        guard let session = loggedExercise.session,
              !loggedExercise.isDeleted,
              loggedExercise.exercise?.id != exercise.id,
              session.sortedLoggedExercises.contains(where: { $0.id == loggedExercise.id }) else {
            throw ActiveWorkoutEngineError.invalidExerciseSwap
        }

        let setKinds = try initialSetKinds(
            for: exercise,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
        let originalSessionUpdatedAt = session.updatedAt
        let originalLoggedExerciseUpdatedAt = loggedExercise.updatedAt
        let originalLoggedExerciseDeletedAt = loggedExercise.deletedAt
        let originalSetStates = loggedExercise.sets.map { set in
            (set: set, updatedAt: set.updatedAt, deletedAt: set.deletedAt)
        }
        // The replacement takes the slot, including its place in a superset.
        let replacement = LoggedExercise(
            orderIndex: loggedExercise.orderIndex,
            exercise: exercise,
            supersetGroupID: loggedExercise.supersetGroupID,
            createdAt: now,
            updatedAt: now
        )
        replacement.session = session
        context.insert(replacement)

        let replacementSets = setKinds.enumerated().map { index, kind in
            LoggedSet(orderIndex: index, kind: kind, createdAt: now, updatedAt: now)
        }
        for set in replacementSets {
            set.loggedExercise = replacement
            context.insert(set)
            replacement.sets.append(set)
        }
        session.loggedExercises.append(replacement)

        loggedExercise.markDeleted(now: now)
        for set in loggedExercise.sets {
            set.markDeleted(now: now)
        }
        session.touch(now: now)

        do {
            try save(context)
            for set in loggedExercise.sets { restTimer.cancel(ifStartedBy: set.id) }
            return replacement
        } catch {
            session.loggedExercises.removeAll { $0.id == replacement.id }
            for set in replacementSets {
                context.delete(set)
            }
            context.delete(replacement)
            loggedExercise.updatedAt = originalLoggedExerciseUpdatedAt
            loggedExercise.deletedAt = originalLoggedExerciseDeletedAt
            for state in originalSetStates {
                state.set.updatedAt = state.updatedAt
                state.set.deletedAt = state.deletedAt
            }
            session.updatedAt = originalSessionUpdatedAt
            context.rollback()
            throw error
        }
    }

    func reorderLoggedExercises(
        in session: WorkoutSession,
        orderedIDs: [UUID],
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let visibleIDs = session.sortedLoggedExercises.map(\.id)
        guard orderedIDs.count == visibleIDs.count, Set(orderedIDs) == Set(visibleIDs) else {
            throw ActiveWorkoutEngineError.invalidExerciseReorder
        }

        try applyExerciseListChanges(
            in: session, orderedIDs: orderedIDs,
            baseline: WorkoutExerciseListSnapshot(session: session),
            context: context, now: now, save: save
        )
    }

    /// Commits a sheet's removals and order together. Restore only the fields
    /// touched here on failure, preserving unrelated drafts and outbox work.
    func applyExerciseListChanges(
        in session: WorkoutSession,
        orderedIDs: [UUID],
        baseline: WorkoutExerciseListSnapshot,
        additions: [WorkoutExerciseListDraft.Addition] = [],
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let remainingIDs = Set(orderedIDs)
        guard !session.isDeleted, session.status == .active, !hasPendingSetSave,
              baseline == WorkoutExerciseListSnapshot(session: session),
              remainingIDs.count == orderedIDs.count,
              remainingIDs.isSubset(of: Set(baseline.exercises.map(\.id) + additions.map(\.id))) else {
            throw ActiveWorkoutEngineError.invalidExerciseReorder
        }

        let visibleExercises = session.sortedLoggedExercises
        let removedExercises = visibleExercises.filter { !remainingIDs.contains($0.id) }
        let removedSets = removedExercises.flatMap(\.sortedSets)

        let originalSessionUpdatedAt = session.updatedAt
        let originalExerciseStates = visibleExercises.map {
            (exercise: $0, orderIndex: $0.orderIndex, supersetGroupID: $0.supersetGroupID,
             hasLocalSupersetChange: $0.hasLocalSupersetChange, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt)
        }
        let originalSetStates = removedSets.map {
            (set: $0, updatedAt: $0.updatedAt, deletedAt: $0.deletedAt)
        }
        let pending = additions.filter { remainingIDs.contains($0.id) }
        guard pending.allSatisfy({ !$0.exercise.isArchived && !$0.exercise.isDeleted
            && $0.exercise.isVisible(to: ownerTokenIdentifier) }) else {
            throw ActiveWorkoutEngineError.invalidExerciseReorder
        }
        let inserted = try insertExercises(
            pending.map(\.exercise), to: session, ownerTokenIdentifier: ownerTokenIdentifier,
            context: context, save: { _ in }, plannedSetKinds: pending.map(\.initialSetKinds)
        )
        let exercisesByID = Dictionary(uniqueKeysWithValues:
            visibleExercises.map { ($0.id, $0) } + zip(pending, inserted).map { ($0.0.id, $0.1) }
        )
        do {
            var didChangeOrder = false

            for (index, id) in orderedIDs.enumerated() {
                guard let loggedExercise = exercisesByID[id] else {
                    throw ActiveWorkoutEngineError.invalidExerciseReorder
                }

                if loggedExercise.orderIndex != index {
                    loggedExercise.orderIndex = index
                    loggedExercise.touch(now: now)
                    didChangeOrder = true
                }
            }

            // The sheet moves supersets as blocks. Removals can still leave one
            // exercise alone, and other callers may split a run.
            let didChangeGrouping = normalizeSupersets(orderedIDs.compactMap { exercisesByID[$0] }, now: now)
            guard didChangeOrder || didChangeGrouping || !removedExercises.isEmpty || !inserted.isEmpty else { return }
            for exercise in removedExercises { exercise.markDeleted(now: now) }
            for set in removedSets { set.markDeleted(now: now) }
            session.touch(now: now)
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--uitest-in-memory-store"),
               arguments.contains("--uitest-fail-reorder-exercises-save-once"),
               injectedReorderExercisesSaveFailureCount == 0 {
                injectedReorderExercisesSaveFailureCount += 1
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            try save(context)
            for set in removedSets { restTimer.cancel(ifStartedBy: set.id) }
        } catch {
            let insertedIDs = Set(inserted.map(\.id))
            session.loggedExercises.removeAll { insertedIDs.contains($0.id) }
            for exercise in inserted {
                for set in exercise.sets { context.delete(set) }
                context.delete(exercise)
            }
            for state in originalExerciseStates {
                state.exercise.orderIndex = state.orderIndex
                state.exercise.supersetGroupID = state.supersetGroupID
                state.exercise.hasLocalSupersetChange = state.hasLocalSupersetChange
                state.exercise.updatedAt = state.updatedAt
                state.exercise.deletedAt = state.deletedAt
            }
            for state in originalSetStates {
                state.set.updatedAt = state.updatedAt
                state.set.deletedAt = state.deletedAt
            }
            session.updatedAt = originalSessionUpdatedAt
            throw error
        }
    }

    enum SupersetChange {
        case joinPrevious
        case joinNext
        case remove
    }

    /// Applies one exercise-menu superset action as a single save.
    func changeSuperset(
        _ change: SupersetChange,
        for loggedExercise: LoggedExercise,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard let session = loggedExercise.session, !session.isDeleted, session.status == .active,
              !hasPendingSetSave else {
            throw ActiveWorkoutEngineError.invalidSupersetChange
        }
        let exercises = session.sortedLoggedExercises
        guard let index = exercises.firstIndex(where: { $0.id == loggedExercise.id }) else {
            throw ActiveWorkoutEngineError.invalidSupersetChange
        }
        let groupIDs = exercises.map(\.supersetGroupID)
        let neighbor: Int? = switch change {
        case .joinPrevious: index - 1
        case .joinNext: index + 1
        case .remove: nil
        }
        let updated: [UUID?]
        if let neighbor {
            guard exercises.indices.contains(neighbor),
                  !SupersetGrouping.areGrouped(groupIDs, index, neighbor) else {
                throw ActiveWorkoutEngineError.invalidSupersetChange
            }
            updated = SupersetGrouping.linking(groupIDs, index, with: neighbor)
        } else {
            guard SupersetGrouping.isGrouped(groupIDs, at: index) else {
                throw ActiveWorkoutEngineError.invalidSupersetChange
            }
            updated = SupersetGrouping.removing(groupIDs, at: index)
        }

        let originalSessionUpdatedAt = session.updatedAt
        let changed = zip(exercises, updated).filter { $0.0.supersetGroupID != $0.1 }
        let originalStates = changed.map {
            (exercise: $0.0, supersetGroupID: $0.0.supersetGroupID,
             hasLocalSupersetChange: $0.0.hasLocalSupersetChange, updatedAt: $0.0.updatedAt)
        }
        guard !changed.isEmpty else { return }
        for (exercise, group) in changed {
            exercise.supersetGroupID = group
            exercise.hasLocalSupersetChange = true
            exercise.touch(now: now)
        }
        do {
            try save(context)
        } catch {
            for state in originalStates {
                state.exercise.supersetGroupID = state.supersetGroupID
                state.exercise.hasLocalSupersetChange = state.hasLocalSupersetChange
                state.exercise.updatedAt = state.updatedAt
            }
            session.updatedAt = originalSessionUpdatedAt
            throw error
        }
    }

    @discardableResult
    func addSet(to loggedExercise: LoggedExercise, context: ModelContext) throws -> LoggedSet {
        let sortedSets = loggedExercise.sortedSets
        let previous = sortedSets.last
        let set = LoggedSet(
            orderIndex: (sortedSets.map(\.orderIndex).max() ?? -1) + 1,
            kind: previous?.kind ?? .working,
            isCompleted: false
        )
        set.loggedExercise = loggedExercise
        context.insert(set)
        loggedExercise.sets.append(set)
        loggedExercise.touch()
        try context.save()
        return set
    }

    func removeSet(_ set: LoggedSet, context: ModelContext, now: Date = .now) throws {
        let loggedExercise = set.loggedExercise
        set.markDeleted(now: now)
        if let loggedExercise {
            reindexSets(for: loggedExercise, now: now)
            loggedExercise.touch(now: now)
        }
        try context.save()
        restTimer.cancel(ifStartedBy: set.id)
    }

    /// Persists a focus-boundary weight/reps draft without turning a local
    /// Active Workout checkpoint into a graph-level timestamp mutation.
    @discardableResult
    func commitActiveSetDraft(
        _ set: LoggedSet,
        values: ActiveWorkoutSetInput.Values,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Bool {
        guard !hasPendingSetSave else { return false }
        let weight = WorkoutNumericInputPolicy.validatedWeight(values.weight)
        let reps = WorkoutNumericInputPolicy.validatedReps(values.reps)
        guard weight != WorkoutNumericInputPolicy.validatedWeight(set.weight)
            || reps != WorkoutNumericInputPolicy.validatedReps(set.reps) else { return false }
        try saveSetAction(.draft(.init(weight: weight, reps: reps)), for: set,
                          context: context, now: now, save: save)
        return true
    }

    func applyActiveSetRPESelection(
        _ set: LoggedSet,
        rpe: Double?,
        preparedValues: ActiveWorkoutSetInput.Values,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard !hasPendingSetSave else { return }
        try saveSetAction(.rpe(preparedValues, rpe), for: set, context: context, now: now, save: save)
    }

    func fillSetFromPrevious(
        _ set: LoggedSet,
        previous: PreviousSetPerformance,
        preparedValues: ActiveWorkoutSetInput.Values? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        guard !set.isCompleted else { return }
        let current = preparedValues ?? .init(weight: set.weight, reps: set.reps)
        let values = ActiveWorkoutSetInput.Values(
            weight: WorkoutNumericInputPolicy.validatedWeight(previous.weight) ?? current.weight,
            reps: WorkoutNumericInputPolicy.validatedReps(previous.reps) ?? current.reps
        )
        try commitActiveSetDraft(set, values: values, context: context, now: now)
    }

    func toggleSetCompletion(
        _ set: LoggedSet,
        preparedValues: ActiveWorkoutSetInput.Values? = nil,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard !hasPendingSetSave else { return }
        try saveSetAction(
            .completion(preparedValues ?? .init(weight: set.weight, reps: set.reps), !set.isCompleted),
            for: set, context: context, now: now, save: save
        )
    }

    func canRetrySetSave(in session: WorkoutSession?) -> Bool {
        guard let pendingSetSave, pendingSetSave.belongs(to: session) else { return false }
        let set = pendingSetSave.set
        return !set.isDeleted && set.modelContext != nil
            && set.loggedExercise?.isDeleted == false
            && set.loggedExercise?.session?.id == session?.id
    }

    func clearSetSaveIfInaccessible(in session: WorkoutSession?) {
        guard let pendingSetSave, !pendingSetSave.belongs(to: session) else { return }
        discardSetSave()
    }

    func retrySetSave(
        in session: WorkoutSession?,
        context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        clearSetSaveIfInaccessible(in: session)
        guard canRetrySetSave(in: session), let pendingSetSave else { return }
        try saveSetAction(pendingSetSave.action, for: pendingSetSave.set, context: context,
                          now: pendingSetSave.date, save: save)
    }

    func discardSetSave() {
        // The failed attempt was already restored. Leaving must never need a save.
        guard hasPendingSetSave else { return }
        pendingSetSave = nil
    }

    private enum SetSaveAction {
        case draft(ActiveWorkoutSetInput.Values)
        case completion(ActiveWorkoutSetInput.Values, Bool)
        case rpe(ActiveWorkoutSetInput.Values, Double?)

        var operation: ActiveWorkoutSetSaveFailure.Operation {
            switch self {
            case .draft: .fieldEdit
            case .completion: .completion
            case .rpe: .rpe
            }
        }
    }

    private struct PendingSetSave {
        let id = UUID()
        let set: LoggedSet
        let action: SetSaveAction
        let date: Date
        let sessionID: UUID?
        let owner: String?

        func belongs(to session: WorkoutSession?) -> Bool {
            guard let session else { return false }
            return session.id == sessionID && session.syncOwnerTokenIdentifier == owner
                && session.status == .active && !session.isDeleted
        }
    }

    private func saveSetAction(
        _ action: SetSaveAction,
        for set: LoggedSet,
        context: ModelContext,
        now: Date,
        save: (ModelContext) throws -> Void
    ) throws {
        let isRetry = pendingSetSave != nil
        let before = SetSaveSnapshot(set)
        switch action {
        case let .draft(values):
            set.weight = values.weight
            set.reps = values.reps
            set.touchActiveDraft(now: now)
        case let .rpe(values, selection):
            let rpe = WorkoutNumericInputPolicy.validatedRPE(selection)
            let weight = WorkoutNumericInputPolicy.validatedWeight(values.weight)
            let reps = WorkoutNumericInputPolicy.validatedReps(values.reps)
            let completesSet = rpe != nil && !set.isCompleted
            guard completesSet
                || weight != WorkoutNumericInputPolicy.validatedWeight(set.weight)
                || reps != WorkoutNumericInputPolicy.validatedReps(set.reps)
                || rpe != WorkoutNumericInputPolicy.validatedRPE(set.rpe) else {
                discardSetSave()
                return
            }
            set.weight = weight
            set.reps = reps
            set.rpe = rpe
            if completesSet {
                set.isCompleted = true
                set.completedAt = now
                set.touch(now: now)
            } else {
                set.touchActiveDraft(now: now)
            }
        case let .completion(values, isCompleted):
            set.weight = WorkoutNumericInputPolicy.validatedWeight(values.weight)
            set.reps = WorkoutNumericInputPolicy.validatedReps(values.reps)
            set.isCompleted = isCompleted
            set.completedAt = isCompleted ? now : nil
            set.touch(now: now)
        }
        let roundPartners = !before.isCompleted && set.isCompleted ? completeSupersetRound(of: set, now: now) : []
        do {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--uitest-in-memory-store"),
               arguments.contains("--uitest-fail-active-set-save-always")
                || (arguments.contains("--uitest-fail-active-set-save-once") && injectedSetSaveFailureCount == 0) {
                injectedSetSaveFailureCount += 1
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            try save(context)
            discardSetSave()
            if before.isCompleted != set.isCompleted {
                if set.isCompleted, restTimer.isEnabled, let exercise = set.loggedExercise,
                   let session = exercise.session, session.status == .active {
                    let records = (try? context.fetch(FetchDescriptor<UserSettings>())) ?? []
                    let settings = UserSettings.visibleSettingsRecords(from: records,
                        ownerTokenIdentifier: restSettingsOwnerTokenIdentifier ?? session.syncOwnerTokenIdentifier).first
                    restTimer.start(sessionID: session.id, setID: set.id,
                        duration: RestDurationLookup.seconds(for: exercise, settings: settings))
                } else {
                    restTimer.cancel(ifStartedBy: set.id)
                }
            }
        } catch {
            for (partner, snapshot) in roundPartners.reversed() { snapshot.restore(partner) }
            before.restore(set)
            pendingSetSave = PendingSetSave(set: set, action: action, date: now,
                sessionID: set.loggedExercise?.session?.id,
                owner: set.loggedExercise?.session?.syncOwnerTokenIdentifier)
            if !isRetry {
                reportSetSaveFailure(ActiveWorkoutSetSaveFailure(operation: action.operation, error: error))
            }
            throw error
        }
    }

    /// Checking set N in a superset checks set N on its partners. Each fills
    /// empty fields the way its own check would: from the sets above it, then
    /// from last time. Returns the partners changed, for restoring on failure.
    private func completeSupersetRound(of set: LoggedSet, now: Date) -> [(LoggedSet, SetSaveSnapshot)] {
        guard let exercise = set.loggedExercise, let session = exercise.session, session.status == .active,
              let position = exercise.sortedSets.firstIndex(where: { $0.id == set.id }),
              let block = SupersetGrouping.blocks(session.sortedLoggedExercises, groupID: \.supersetGroupID)
                .first(where: { $0.members.contains { $0.id == exercise.id } }),
              block.isSuperset else { return [] }

        var partners: [(LoggedSet, SetSaveSnapshot)] = []
        for partnerExercise in block.members where partnerExercise.id != exercise.id {
            let sets = partnerExercise.sortedSets
            // An exercise with fewer sets sits out the extra rounds.
            guard sets.indices.contains(position), !sets[position].isCompleted else { continue }
            let partner = sets[position]
            let snapshot = SetSaveSnapshot(partner)
            let above = ActiveWorkoutSetSuggestions.resolve(for: sets.map { .init(weight: $0.weight, reps: $0.reps) })[position]
            let previous = previousSetsByLoggedExerciseID[partnerExercise.id].flatMap {
                $0.indices.contains(position) ? $0[position] : nil
            }
            partner.weight = WorkoutNumericInputPolicy.validatedWeight(partner.weight)
                ?? WorkoutNumericInputPolicy.validatedWeight(above.weight)
                ?? WorkoutNumericInputPolicy.validatedWeight(previous?.weight)
            partner.reps = WorkoutNumericInputPolicy.validatedReps(partner.reps)
                ?? WorkoutNumericInputPolicy.validatedReps(above.reps)
                ?? WorkoutNumericInputPolicy.validatedReps(previous?.reps)
            partner.isCompleted = true
            partner.completedAt = now
            partner.touch(now: now)
            partners.append((partner, snapshot))
        }
        return partners
    }

    /// Only the fields changed by a set edit, never the whole model context.
    private struct SetSaveSnapshot {
        let weight: Double?
        let reps: Int?
        let rpe: Double?
        let isCompleted: Bool
        let completedAt: Date?
        let updatedAt: Date
        let exerciseUpdatedAt: Date?
        let sessionUpdatedAt: Date?

        init(_ set: LoggedSet) {
            weight = set.weight
            reps = set.reps
            rpe = set.rpe
            isCompleted = set.isCompleted
            completedAt = set.completedAt
            updatedAt = set.updatedAt
            exerciseUpdatedAt = set.loggedExercise?.updatedAt
            sessionUpdatedAt = set.loggedExercise?.session?.updatedAt
        }

        func restore(_ set: LoggedSet) {
            set.weight = weight
            set.reps = reps
            set.rpe = rpe
            set.isCompleted = isCompleted
            set.completedAt = completedAt
            set.updatedAt = updatedAt
            if let exerciseUpdatedAt { set.loggedExercise?.updatedAt = exerciseUpdatedAt }
            if let sessionUpdatedAt { set.loggedExercise?.session?.updatedAt = sessionUpdatedAt }
        }
    }

    func finalizeWorkoutTitle(_ session: WorkoutSession, context: ModelContext) throws {
        applyFinalWorkoutTitle(to: session)
        session.touch()
        try context.save()
    }

    /// Applies a draft title in a single commit. Text fields hold keystrokes in
    /// view-local drafts and call this on focus loss; nothing in the workout
    /// form may write + save per keystroke.
    func commitWorkoutTitle(_ title: String, session: WorkoutSession, context: ModelContext) throws {
        session.title = title
        try finalizeWorkoutTitle(session, context: context)
    }

    func updateWorkoutNotes(_ notes: String, session: WorkoutSession, context: ModelContext) throws {
        session.notes = notes
        session.touch()
        try context.save()
    }

    func updateExerciseNotes(_ notes: String, loggedExercise: LoggedExercise, context: ModelContext) throws {
        loggedExercise.notes = notes
        loggedExercise.touch()
        try context.save()
    }

    func finishWorkout(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        syncScheduler: SyncScheduler? = nil,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try finishWorkouts([session], ownerTokenIdentifier: ownerTokenIdentifier,
            syncScheduler: syncScheduler, context: context, now: now, save: save)
    }

    /// Account transitions may resolve legacy records together. Stage every
    /// graph in the same transaction; timer and sync effects follow the save.
    func finishWorkouts(
        _ sessions: [WorkoutSession],
        ownerTokenIdentifier: String? = nil,
        syncScheduler: SyncScheduler? = nil,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try persistWorkoutFinalization(sessions, context: context, save: save) { session in
            let effectiveOwner = session.syncOwnerTokenIdentifier ?? ownerTokenIdentifier
            applyFinalWorkoutTitle(to: session)
            session.syncOwnerTokenIdentifier = effectiveOwner
            session.status = .completed
            session.endedAt = now
            session.durationSeconds = max(0, Int(now.timeIntervalSince(session.startedAt)))
            session.touch(now: now)
            var records = [SyncOutboxRecorder.CreateRecord(entityKind: .workoutSession, entityID: session.id)]
            for exercise in session.sortedLoggedExercises {
                records.append(.init(entityKind: .loggedExercise, entityID: exercise.id))
                records += exercise.sortedSets.map { .init(entityKind: .loggedSet, entityID: $0.id) }
            }
            try SyncOutboxRecorder().recordCreates(records,
                ownerTokenIdentifier: effectiveOwner, context: context, now: now)
        }
        if let owner = syncScheduler?.currentOwnerTokenIdentifier,
           sessions.contains(where: { $0.syncOwnerTokenIdentifier == owner }) {
            syncScheduler?.requestSync()
        }
    }

    func discardWorkout(_ session: WorkoutSession, context: ModelContext,
                        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try discardWorkouts([session], context: context, save: save)
    }

    func discardWorkouts(_ sessions: [WorkoutSession], context: ModelContext,
                         save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let now = Date.now
        try persistWorkoutFinalization(sessions, context: context, save: save) { session in
            session.status = .discarded
            session.touch(now: now)
        }
    }

    private func persistWorkoutFinalization(
        _ sessions: [WorkoutSession], context: ModelContext,
        save: (ModelContext) throws -> Void,
        mutate: (WorkoutSession) throws -> Void
    ) throws {
        guard !sessions.isEmpty else { return }
        let baselines = sessions.map(WorkoutFinalizationSnapshot.init)
        do {
            for session in sessions { try mutate(session) }
            try save(context)
        } catch {
            context.rollback()
            // Rollback alone may leave observed model instances at attempted
            // values. Restore every captured workout, including earlier ones.
            for (session, baseline) in zip(sessions, baselines) { baseline.restore(session) }
            throw error
        }
        for session in sessions {
            restTimer.cancel(sessionID: session.id)
            if activeSessionID == session.id { activeSessionID = nil }
        }
    }

    private struct WorkoutFinalizationSnapshot {
        let title: String
        let owner: String?
        let status: WorkoutSessionStatus
        let endedAt: Date?
        let duration: Int
        let updatedAt: Date

        init(_ session: WorkoutSession) {
            title = session.title
            owner = session.syncOwnerTokenIdentifier
            status = session.status
            endedAt = session.endedAt
            duration = session.durationSeconds
            updatedAt = session.updatedAt
        }

        func restore(_ session: WorkoutSession) {
            session.title = title
            session.syncOwnerTokenIdentifier = owner
            session.status = status
            session.endedAt = endedAt
            session.durationSeconds = duration
            session.updatedAt = updatedAt
        }
    }

    /// Visibility must never be used as proof that the device has no active workout.
    /// This check reveals no outgoing-owner model to the caller and never finalizes it.
    private func requireWorkoutStartAllowed(ownerTokenIdentifier: String?, context: ModelContext) throws {
        guard !isAccountTransitionInProgress, !isAccountManagementPresented else {
            throw ActiveWorkoutEngineError.accountTransitionInProgress
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.status == .active && !$0.isDeleted }
        guard sessions.count <= 1 else { throw ActiveWorkoutEngineError.multipleActiveWorkouts }
        if sessions.contains(where: {
            $0.status == .active && !$0.isDeleted
                && $0.syncOwnerTokenIdentifier != nil
                && $0.syncOwnerTokenIdentifier != ownerTokenIdentifier
        }) {
            throw ActiveWorkoutEngineError.anotherOwnerHasActiveWorkout
        }
    }

    private func currentActiveSession(ownerTokenIdentifier: String?, context: ModelContext) throws -> WorkoutSession? {
        let activeSessions = WorkoutSession.visibleActiveSessions(
            from: try context.fetch(FetchDescriptor<WorkoutSession>()),
            ownerTokenIdentifier: ownerTokenIdentifier
        )
            .sorted { $0.startedAt > $1.startedAt }

        return activeSessions.first
    }

    private func isVisiblePastWorkout(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) throws -> Bool {
        WorkoutSession.visibleCompletedSessions(
            from: try context.fetch(FetchDescriptor<WorkoutSession>()),
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        .contains { $0.id == session.id }
    }

    /// One blank row per completed set from the exercise's last performance,
    /// keeping each row's set kind, or a single working set when there is none.
    private func initialSetKinds(
        for exercise: Exercise,
        ownerTokenIdentifier: String?,
        context: ModelContext
    ) throws -> [SetKind] {
        initialSetKinds(
            for: exercise, ownerTokenIdentifier: ownerTokenIdentifier,
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>())
        )
    }

    func initialSetKinds(
        for exercise: Exercise,
        ownerTokenIdentifier: String?,
        sessions: [WorkoutSession]
    ) -> [SetKind] {
        let route = ExerciseHistoryRoute(
            exerciseID: exercise.id,
            name: exercise.name,
            equipmentRaw: exercise.equipmentRaw
        )
        let kinds = PreviousSetPerformance.lastCompletedSetKinds(
            for: route,
            in: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        return kinds.isEmpty ? [.working] : kinds
    }

    private func reindexLoggedExercises(for session: WorkoutSession, now: Date) {
        for (index, loggedExercise) in session.sortedLoggedExercises.enumerated() where loggedExercise.orderIndex != index {
            loggedExercise.orderIndex = index
            loggedExercise.touch(now: now)
        }
    }

    /// Keeps stored grouping in the shape readers trust after a structure change.
    @discardableResult
    private func normalizeSupersets(_ orderedExercises: [LoggedExercise], now: Date) -> Bool {
        let normalized = SupersetGrouping.normalized(orderedExercises.map(\.supersetGroupID))
        var didChange = false
        for (exercise, group) in zip(orderedExercises, normalized) where exercise.supersetGroupID != group {
            exercise.supersetGroupID = group
            exercise.hasLocalSupersetChange = true
            exercise.touch(now: now)
            didChange = true
        }
        return didChange
    }

    private func reindexSets(for loggedExercise: LoggedExercise, now: Date = .now) {
        for (index, set) in loggedExercise.sortedSets.enumerated() where set.orderIndex != index {
            set.orderIndex = index
            set.touch(now: now)
        }
    }

    private func applyFinalWorkoutTitle(to session: WorkoutSession) {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.title = trimmed.isEmpty ? WorkoutSession.defaultTitle : trimmed
    }
}
