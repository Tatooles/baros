import Foundation
import Observation
import SwiftData

enum ActiveWorkoutEngineError: LocalizedError, Equatable {
    case invalidExerciseReorder
    case pastWorkoutUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidExerciseReorder:
            return "Workout exercises changed. Review the current order and try again."
        case .pastWorkoutUnavailable:
            return "That past workout is no longer available. Choose another workout and try again."
        }
    }
}

@Observable
final class ActiveWorkoutEngine {
    var activeSessionID: UUID?
    var isStartingWorkout = false
    var lastErrorMessage: String?

    @ObservationIgnored private let save: (ModelContext) throws -> Void

    init(save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.save = save
    }

    /// Every Active Workout save rolls back on failure. Callers keep the user's
    /// keystrokes in a view-local draft and surface the error for a retry, so a
    /// failed save must not leave the models dirty:
    /// `SyncOutboxTransaction`'s preflight would otherwise treat the workout's
    /// own pending edits as unrelated state and discard them when it is
    /// finished, reporting `unexpectedUnsavedDomainChanges` instead of the real
    /// failure.
    private func persist(_ context: ModelContext) throws {
        do {
            try save(context)
        } catch {
            // Active Workout saves record no outbox intents, so any outbox
            // bookkeeping in the shared context belongs to a suspended sync and
            // must survive this rollback.
            OutboxBookkeepingSnapshot.rollbackPreservingBookkeeping(in: context)
            throw error
        }
    }

    func loadActiveSession(ownerTokenIdentifier: String? = nil, context: ModelContext) {
        do {
            activeSessionID = try currentActiveSession(ownerTokenIdentifier: ownerTokenIdentifier, context: context)?.id
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
            title: "Workout",
            startedAt: now,
            status: .active,
            source: .blank,
            createdAt: now,
            updatedAt: now,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        context.insert(session)
        try persist(context)
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
            referenceNotes: pastSession.notes,
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
                referenceNotes: pastLoggedExercise.notes,
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

        try persist(context)
        activeSessionID = session.id
        return session
    }

    @discardableResult
    func addExercise(_ exercise: Exercise, to session: WorkoutSession, context: ModelContext) throws -> LoggedExercise {
        let nextIndex = (session.sortedLoggedExercises.map(\.orderIndex).max() ?? -1) + 1
        let loggedExercise = LoggedExercise(orderIndex: nextIndex, exercise: exercise)
        loggedExercise.session = session
        context.insert(loggedExercise)

        let firstSet = LoggedSet(orderIndex: 0)
        firstSet.loggedExercise = loggedExercise
        context.insert(firstSet)
        loggedExercise.sets.append(firstSet)
        session.loggedExercises.append(loggedExercise)
        session.touch()
        try persist(context)
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
        try persist(context)
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
        try persist(context)
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
        try persist(context)
        return set
    }

    func removeSet(_ set: LoggedSet, context: ModelContext, now: Date = .now) throws {
        let loggedExercise = set.loggedExercise
        set.markDeleted(now: now)
        if let loggedExercise {
            reindexSets(for: loggedExercise, now: now)
            loggedExercise.touch(now: now)
        }
        try persist(context)
    }

    func updateSet(_ set: LoggedSet, weight: Double?, reps: Int?, rpe: Double?, context: ModelContext) throws {
        set.weight = WorkoutNumericInputPolicy.validatedWeight(weight)
        set.reps = WorkoutNumericInputPolicy.validatedReps(reps)
        set.rpe = WorkoutNumericInputPolicy.validatedRPE(rpe)
        set.touch()
        try persist(context)
    }

    func fillSetFromPrevious(_ set: LoggedSet, previous: PreviousSetPerformance, context: ModelContext) throws {
        var didChange = false

        if WorkoutNumericInputPolicy.validatedWeight(set.weight) == nil,
           let weight = WorkoutNumericInputPolicy.validatedWeight(previous.weight) {
            set.weight = weight
            didChange = true
        }

        if WorkoutNumericInputPolicy.validatedReps(set.reps) == nil,
           let reps = WorkoutNumericInputPolicy.validatedReps(previous.reps) {
            set.reps = reps
            didChange = true
        }

        guard didChange else { return }

        set.touch()
        try persist(context)
    }

    func toggleSetCompletion(_ set: LoggedSet, context: ModelContext, now: Date = .now) throws {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? now : nil
        set.touch(now: now)
        try persist(context)
    }

    func finalizeWorkoutTitle(_ session: WorkoutSession, context: ModelContext) throws {
        applyFinalWorkoutTitle(to: session)
        session.touch()
        try persist(context)
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
        try persist(context)
    }

    func updateExerciseNotes(_ notes: String, loggedExercise: LoggedExercise, context: ModelContext) throws {
        loggedExercise.notes = notes
        loggedExercise.touch()
        try persist(context)
    }

    @MainActor
    func finishWorkout(
        _ session: WorkoutSession,
        ownerTokenIdentifier: String? = nil,
        syncOutboxTransaction: SyncOutboxTransaction,
        context: ModelContext,
        now: Date = .now
    ) throws {
        let effectiveOwnerTokenIdentifier = session.syncOwnerTokenIdentifier ?? ownerTokenIdentifier
        let recordCompletedGraph = { (actions: SyncOutboxTransaction.Actions) throws in
            try actions.create(.loggedWorkout(session), now: now) { _ in
                self.applyWorkoutCompletion(
                    to: session,
                    ownerTokenIdentifier: effectiveOwnerTokenIdentifier,
                    now: now
                )
            }
            // The children already exist locally; completing their parent makes them sync-eligible.
            for loggedExercise in session.sortedLoggedExercises {
                try actions.create(.loggedExercise(loggedExercise), now: now) { _ in }
                for set in loggedExercise.sortedSets {
                    try actions.create(.loggedSet(set), now: now) { _ in }
                }
            }
        }
        if let effectiveOwnerTokenIdentifier {
            try syncOutboxTransaction.perform(
                ownerTokenIdentifier: effectiveOwnerTokenIdentifier,
                operation: recordCompletedGraph
            )
        } else {
            // A workout finished while signed out is still a Logged Workout; its
            // ownerless intents are what carry it to the cloud once claimed.
            try syncOutboxTransaction.performUnclaimed(operation: recordCompletedGraph)
        }
        if activeSessionID == session.id {
            activeSessionID = nil
        }
    }

    func discardWorkout(_ session: WorkoutSession, context: ModelContext) throws {
        session.status = .discarded
        session.touch()
        try persist(context)
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
            try persist(context)
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
        session.title = trimmed.isEmpty ? "Workout" : trimmed
    }

    private func applyWorkoutCompletion(
        to session: WorkoutSession,
        ownerTokenIdentifier: String?,
        now: Date
    ) {
        applyFinalWorkoutTitle(to: session)
        session.syncOwnerTokenIdentifier = ownerTokenIdentifier
        session.status = .completed
        session.endedAt = now
        session.durationSeconds = max(0, Int(now.timeIntervalSince(session.startedAt)))
        session.touch(now: now)
    }
}
