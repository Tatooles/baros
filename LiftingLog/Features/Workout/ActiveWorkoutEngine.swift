import Foundation
import Observation
import SwiftData

enum ActiveWorkoutEngineError: LocalizedError, Equatable {
    case invalidExerciseReorder

    var errorDescription: String? {
        switch self {
        case .invalidExerciseReorder:
            return "Workout exercises changed. Review the current order and try again."
        }
    }
}

@Observable
final class ActiveWorkoutEngine {
    var activeSessionID: UUID?
    var isStartingWorkout = false
    var lastErrorMessage: String?

    func loadActiveSession(context: ModelContext) {
        do {
            activeSessionID = try currentActiveSession(context: context)?.id
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func startBlankWorkout(context: ModelContext, now: Date = .now) throws -> WorkoutSession {
        if let active = try currentActiveSession(context: context) {
            activeSessionID = active.id
            return active
        }

        isStartingWorkout = true
        defer { isStartingWorkout = false }

        let session = WorkoutSession(title: "Workout", startedAt: now, status: .active, source: .blank, createdAt: now, updatedAt: now)
        context.insert(session)
        try context.save()
        activeSessionID = session.id
        return session
    }

    @discardableResult
    func startWorkout(fromPast pastSession: WorkoutSession, context: ModelContext, now: Date = .now) throws -> WorkoutSession {
        if let active = try currentActiveSession(context: context) {
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
            updatedAt: now
        )
        context.insert(session)

        for pastLoggedExercise in pastSession.sortedLoggedExercises {
            let loggedExercise = LoggedExercise(
                orderIndex: pastLoggedExercise.orderIndex,
                exercise: pastLoggedExercise.exercise,
                exerciseSnapshotName: pastLoggedExercise.exerciseSnapshotName,
                referenceNotes: pastLoggedExercise.notes,
                createdAt: now,
                updatedAt: now
            )
            loggedExercise.session = session
            context.insert(loggedExercise)

            for pastSet in pastLoggedExercise.sortedSets {
                let set = LoggedSet(
                    orderIndex: pastSet.orderIndex,
                    placeholderWeight: pastSet.weight,
                    placeholderReps: pastSet.reps,
                    placeholderRPE: pastSet.rpe,
                    kind: pastSet.kind,
                    isCompleted: false,
                    createdAt: now,
                    updatedAt: now
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
        let loggedExercise = LoggedExercise(orderIndex: nextIndex, exercise: exercise, exerciseSnapshotName: exercise.name)
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
            placeholderWeight: previous?.weight ?? previous?.placeholderWeight,
            placeholderReps: previous?.reps ?? previous?.placeholderReps,
            placeholderRPE: previous?.rpe ?? previous?.placeholderRPE,
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
        set.weight = weight
        set.reps = reps
        set.rpe = rpe
        set.touch()
        try context.save()
    }

    func toggleSetCompletion(_ set: LoggedSet, context: ModelContext, now: Date = .now) throws {
        let willComplete = !set.isCompleted
        if willComplete {
            applyPlaceholderValuesIfNeeded(to: set)
        }

        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? now : nil
        set.touch(now: now)
        try context.save()
    }

    func updateWorkoutTitle(_ title: String, session: WorkoutSession, context: ModelContext) throws {
        session.title = title
        session.touch()
        try context.save()
    }

    func finalizeWorkoutTitle(_ session: WorkoutSession, context: ModelContext) throws {
        applyFinalWorkoutTitle(to: session)
        session.touch()
        try context.save()
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
    func finishWorkout(_ session: WorkoutSession, context: ModelContext, now: Date = .now) throws {
        applyFinalWorkoutTitle(to: session)
        session.status = .completed
        session.endedAt = now
        session.durationSeconds = max(0, Int(now.timeIntervalSince(session.startedAt)))
        session.touch(now: now)
        do {
            let recorder = SyncOutboxRecorder()
            try recorder.recordCreate(
                entityKind: .workoutSession,
                entityID: session.id,
                ownerTokenIdentifier: nil,
                context: context,
                now: now
            )
            for loggedExercise in session.sortedLoggedExercises {
                try recorder.recordCreate(
                    entityKind: .loggedExercise,
                    entityID: loggedExercise.id,
                    ownerTokenIdentifier: nil,
                    context: context,
                    now: now
                )
                for set in loggedExercise.sortedSets {
                    try recorder.recordCreate(
                        entityKind: .loggedSet,
                        entityID: set.id,
                        ownerTokenIdentifier: nil,
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

    private func currentActiveSession(context: ModelContext) throws -> WorkoutSession? {
        let activeSessions = WorkoutSession.visibleActiveSessions(from: try context.fetch(FetchDescriptor<WorkoutSession>()))
            .sorted { $0.startedAt > $1.startedAt }

        if activeSessions.count > 1 {
            for staleSession in activeSessions.dropFirst() {
                staleSession.status = .discarded
            }
            try context.save()
        }

        return activeSessions.first
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

    private func applyPlaceholderValuesIfNeeded(to set: LoggedSet) {
        if set.weight == nil, let placeholderWeight = set.placeholderWeight {
            set.weight = placeholderWeight
        }

        if set.reps == nil, let placeholderReps = set.placeholderReps {
            set.reps = placeholderReps
        }

        if set.rpe == nil, let placeholderRPE = set.placeholderRPE {
            set.rpe = placeholderRPE
        }
    }

    private func applyFinalWorkoutTitle(to session: WorkoutSession) {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.title = trimmed.isEmpty ? "Workout" : trimmed
    }
}
