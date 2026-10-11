import Foundation
import Observation
import SwiftData

enum ActiveWorkoutEngineError: LocalizedError, Equatable {
    case invalidExerciseReorder
    case invalidExerciseSwap
    case pastWorkoutUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidExerciseReorder:
            return "Workout exercises changed. Review the current order and try again."
        case .invalidExerciseSwap:
            return "That exercise can no longer be swapped. Review the workout and try again."
        case .pastWorkoutUnavailable:
            return "That past workout is no longer available. Choose another workout and try again."
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
    var lastErrorMessage: String?
    private var pendingSetSave: PendingSetSave?
    #if DEBUG
    @ObservationIgnored private var injectedSetSaveFailureCount = 0
    #endif
    var hasPendingSetSave: Bool { pendingSetSave != nil }
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

        for pastLoggedExercise in pastSession.sortedLoggedExercises {
            let resolvedEquipmentRaw = pastLoggedExercise.resolvedSnapshotEquipmentRaw
            let resolvedPrimaryMuscleGroupRaw = pastLoggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw
            let loggedExercise = LoggedExercise(
                orderIndex: pastLoggedExercise.orderIndex,
                exercise: pastLoggedExercise.exercise,
                exerciseSnapshotName: pastLoggedExercise.exerciseSnapshotName,
                exerciseSnapshotEquipmentRaw: resolvedEquipmentRaw,
                exerciseSnapshotPrimaryMuscleGroupRaw: resolvedPrimaryMuscleGroupRaw,
                sourceLoggedExerciseID: pastLoggedExercise.id,
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

    @discardableResult
    func addExercise(
        _ exercise: Exercise,
        to session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext
    ) throws -> LoggedExercise {
        let setKinds = try initialSetKinds(
            for: exercise,
            ownerTokenIdentifier: ownerTokenIdentifier,
            context: context
        )
        let nextIndex = (session.sortedLoggedExercises.map(\.orderIndex).max() ?? -1) + 1
        let loggedExercise = LoggedExercise(orderIndex: nextIndex, exercise: exercise)
        loggedExercise.session = session
        context.insert(loggedExercise)

        for (index, kind) in setKinds.enumerated() {
            let set = LoggedSet(orderIndex: index, kind: kind)
            set.loggedExercise = loggedExercise
            context.insert(set)
            loggedExercise.sets.append(set)
        }
        session.loggedExercises.append(loggedExercise)
        session.touch()
        try context.save()
        return loggedExercise
    }

    func removeLoggedExercise(_ loggedExercise: LoggedExercise, context: ModelContext, now: Date = .now) throws {
        let session = loggedExercise.session
        loggedExercise.markDeleted(now: now)
        for set in loggedExercise.sets {
            set.markDeleted(now: now)
        }
        if let session {
            reindexLoggedExercises(for: session, now: now)
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
        let replacement = LoggedExercise(
            orderIndex: loggedExercise.orderIndex,
            exercise: exercise,
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
        now: Date = .now
    ) throws {
        let visibleExercises = session.sortedLoggedExercises
        let visibleIDs = visibleExercises.map(\.id)
        guard orderedIDs.count == visibleIDs.count, Set(orderedIDs) == Set(visibleIDs) else {
            throw ActiveWorkoutEngineError.invalidExerciseReorder
        }

        let exercisesByID = Dictionary(uniqueKeysWithValues: visibleExercises.map { ($0.id, $0) })
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

        guard didChangeOrder else { return }
        session.touch(now: now)
        try context.save()
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
                if set.isCompleted, let exercise = set.loggedExercise,
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

    @MainActor
    func finishWorkout(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        syncScheduler: SyncScheduler? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        let effectiveOwnerTokenIdentifier = session.syncOwnerTokenIdentifier ?? ownerTokenIdentifier
        applyFinalWorkoutTitle(to: session)
        session.syncOwnerTokenIdentifier = effectiveOwnerTokenIdentifier
        session.status = .completed
        session.endedAt = now
        session.durationSeconds = max(0, Int(now.timeIntervalSince(session.startedAt)))
        session.touch(now: now)
        do {
            let recorder = SyncOutboxRecorder()
            var records = [SyncOutboxRecorder.CreateRecord(entityKind: .workoutSession, entityID: session.id)]
            for loggedExercise in session.sortedLoggedExercises {
                records.append(.init(
                    entityKind: .loggedExercise,
                    entityID: loggedExercise.id
                ))
                for set in loggedExercise.sortedSets {
                    records.append(.init(
                        entityKind: .loggedSet,
                        entityID: set.id
                    ))
                }
            }
            try recorder.recordCreates(
                records,
                ownerTokenIdentifier: effectiveOwnerTokenIdentifier,
                context: context,
                now: now
            )
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        restTimer.cancel(sessionID: session.id)
        if activeSessionID == session.id {
            activeSessionID = nil
        }
        if syncScheduler?.currentOwnerTokenIdentifier == effectiveOwnerTokenIdentifier,
           effectiveOwnerTokenIdentifier != nil {
            syncScheduler?.requestSync()
        }
    }

    func discardWorkout(_ session: WorkoutSession, context: ModelContext) throws {
        session.status = .discarded
        session.touch()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        restTimer.cancel(sessionID: session.id)
        if activeSessionID == session.id {
            activeSessionID = nil
        }
    }

    private func currentActiveSession(ownerTokenIdentifier: String?, context: ModelContext) throws -> WorkoutSession? {
        let activeSessions = WorkoutSession.visibleActiveSessions(
            from: try context.fetch(FetchDescriptor<WorkoutSession>()),
            ownerTokenIdentifier: ownerTokenIdentifier
        )
            .sorted { $0.startedAt > $1.startedAt }

        if activeSessions.count > 1 {
            for staleSession in activeSessions.dropFirst() {
                staleSession.status = .discarded
            }
            try context.save()
        }

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
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
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
