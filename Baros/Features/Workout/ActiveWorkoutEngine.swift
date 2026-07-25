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

        try context.save()
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
    }

    func updateSet(_ set: LoggedSet, weight: Double?, reps: Int?, rpe: Double?, context: ModelContext) throws {
        set.weight = WorkoutNumericInputPolicy.validatedWeight(weight)
        set.reps = WorkoutNumericInputPolicy.validatedReps(reps)
        set.rpe = WorkoutNumericInputPolicy.validatedRPE(rpe)
        set.touch()
        try context.save()
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
        try context.save()
    }

    func toggleSetCompletion(_ set: LoggedSet, context: ModelContext, now: Date = .now) throws {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? now : nil
        set.touch(now: now)
        try context.save()
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
            try recorder.recordCreate(
                entityKind: .workoutSession,
                entityID: session.id,
                ownerTokenIdentifier: effectiveOwnerTokenIdentifier,
                context: context,
                now: now
            )
            for loggedExercise in session.sortedLoggedExercises {
                try recorder.recordCreate(
                    entityKind: .loggedExercise,
                    entityID: loggedExercise.id,
                    ownerTokenIdentifier: effectiveOwnerTokenIdentifier,
                    context: context,
                    now: now
                )
                for set in loggedExercise.sortedSets {
                    try recorder.recordCreate(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        ownerTokenIdentifier: effectiveOwnerTokenIdentifier,
                        context: context,
                        now: now
                    )
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
}
