import Foundation

struct PreviousSetPerformance: Equatable {
    let weight: Double?
    let reps: Int?

    func displayText(weightUnit: MeasurementUnit) -> String {
        let displayWeight = weightUnit.displayWeight(
            fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(weight)
        )
        let weightText = displayWeight.map(WorkoutFormatters.number)
        let repsText = WorkoutNumericInputPolicy.validatedReps(reps).map { WorkoutFormatters.number(Double($0)) }

        switch (weightText, repsText) {
        case let (.some(weightText), .some(repsText)):
            return "\(weightText) × \(repsText)"
        case let (.none, .some(repsText)):
            return "- × \(repsText)"
        case let (.some(weightText), .none):
            return "\(weightText) × -"
        case (.none, .none):
            return "—"
        }
    }

    static func lastCompletedSets(
        for loggedExercise: LoggedExercise,
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?,
        sourceSessionID: UUID? = nil
    ) -> [PreviousSetPerformance] {
        lastCompletedSetsByExerciseID(
            for: [loggedExercise],
            in: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier,
            sourceSessionID: sourceSessionID
        )[loggedExercise.id] ?? []
    }

    static func lastCompletedSetsByExerciseID(
        for loggedExercises: [LoggedExercise],
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?,
        sourceSessionID: UUID? = nil
    ) -> [UUID: [PreviousSetPerformance]] {
        if let sourceSessionID {
            return lastCompletedSetsByExerciseIDFromSourceSession(
                for: loggedExercises,
                in: sessions,
                ownerTokenIdentifier: ownerTokenIdentifier,
                sourceSessionID: sourceSessionID
            )
        }

        return lastCompletedSetsByExerciseIDFromHistory(
            for: loggedExercises,
            in: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
    }

    private static func lastCompletedSetsByExerciseIDFromHistory(
        for loggedExercises: [LoggedExercise],
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?
    ) -> [UUID: [PreviousSetPerformance]] {
        let routeIDByLoggedExerciseID = Dictionary(
            uniqueKeysWithValues: loggedExercises.map { loggedExercise in
                (loggedExercise.id, ExerciseHistoryRoute(loggedExercise: loggedExercise).id)
            }
        )
        let requestedRouteIDs = Set(routeIDByLoggedExerciseID.values)
        guard !requestedRouteIDs.isEmpty else { return [:] }

        let previousSetsByRouteID = lastCompletedSetsByRouteID(
            matching: requestedRouteIDs,
            in: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        )

        return Dictionary(
            uniqueKeysWithValues: routeIDByLoggedExerciseID.map { loggedExerciseID, routeID in
                (loggedExerciseID, previousSetsByRouteID[routeID] ?? [])
            }
        )
    }

    private static func lastCompletedSetsByExerciseIDFromSourceSession(
        for loggedExercises: [LoggedExercise],
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?,
        sourceSessionID: UUID
    ) -> [UUID: [PreviousSetPerformance]] {
        guard let sourceSession = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).first(where: { $0.id == sourceSessionID }) else {
            return Dictionary(uniqueKeysWithValues: loggedExercises.map { ($0.id, []) })
        }

        let sourceEntriesByID = Dictionary(
            uniqueKeysWithValues: sourceSession.sortedLoggedExercises.map { ($0.id, $0) }
        )

        let unlinkedExercises = loggedExercises.filter { $0.sourceLoggedExerciseID == nil }
        let historyForUnlinkedExercises = lastCompletedSetsByExerciseIDFromHistory(
            for: unlinkedExercises,
            in: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        )

        return Dictionary(
            uniqueKeysWithValues: loggedExercises.map { loggedExercise in
                if let sourceLoggedExerciseID = loggedExercise.sourceLoggedExerciseID,
                   let sourceLoggedExercise = sourceEntriesByID[sourceLoggedExerciseID] {
                    return (
                        loggedExercise.id,
                        sourceSetPerformances(for: loggedExercise, in: sourceLoggedExercise)
                    )
                }

                return (loggedExercise.id, historyForUnlinkedExercises[loggedExercise.id] ?? [])
            }
        )
    }

    private static func lastCompletedSetsByRouteID(
        matching routeIDs: Set<String>,
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?
    ) -> [String: [PreviousSetPerformance]] {
        let sortedCompletedSessions = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        .sorted { lhs, rhs in
            if lhs.startedAt == rhs.startedAt {
                return lhs.title < rhs.title
            }
            return lhs.startedAt > rhs.startedAt
        }

        var result: [String: [PreviousSetPerformance]] = [:]

        for session in sortedCompletedSessions {
            for loggedExercise in session.sortedLoggedExercises {
                let routeID = ExerciseHistoryRoute(loggedExercise: loggedExercise).id
                guard routeIDs.contains(routeID), result[routeID] == nil else { continue }

                let completedSets = loggedExercise.sortedSets.filter(\.isCompleted)
                guard !completedSets.isEmpty else { continue }

                result[routeID] = completedSets.map { makePerformance(from: $0) }
            }

            if result.count == routeIDs.count {
                break
            }
        }

        return result
    }

    private static func sourceSetPerformances(
        for activeLoggedExercise: LoggedExercise,
        in sourceLoggedExercise: LoggedExercise
    ) -> [PreviousSetPerformance] {
        let activeSets = activeLoggedExercise.sortedSets

        guard let lastLinkedIndex = activeSets.lastIndex(where: { $0.sourceLoggedSetID != nil }) else {
            return []
        }

        // Align each cloned row to its specific source set so rows keep their own
        // previous values even after an earlier row is deleted or the rows are
        // reordered. Rows added after cloning carry no source link and always sort
        // after the cloned rows, so dropping everything past the last linked row
        // leaves them with no previous value rather than reusing a source set.
        let sourceSetsByID = Dictionary(
            uniqueKeysWithValues: sourceLoggedExercise.sortedSets.map { ($0.id, $0) }
        )

        return activeSets.prefix(through: lastLinkedIndex).map { activeSet in
            if let sourceSetID = activeSet.sourceLoggedSetID,
               let sourceSet = sourceSetsByID[sourceSetID] {
                return makePerformance(from: sourceSet)
            }

            return PreviousSetPerformance(weight: nil, reps: nil)
        }
    }

    private static func makePerformance(from set: LoggedSet) -> PreviousSetPerformance {
        PreviousSetPerformance(weight: set.weight, reps: set.reps)
    }

    /// Captures everything the previous-set lookup depends on, so callers can
    /// cache the (history-scanning) lookup and recompute only when this key
    /// changes. Deliberately ignores in-progress value edits on the active
    /// session — weight/reps/RPE/completion typing must not invalidate the
    /// cache — while structural edits (rows, exercises, ordering, source
    /// links) and any change to completed history do.
    struct CacheKey: Equatable {
        private struct ExerciseEntry: Equatable {
            let id: UUID
            let routeID: String
            let sourceLoggedExerciseID: UUID?
            let setIDs: [UUID]
        }

        private let sessionID: UUID
        private let sourceSessionID: UUID?
        private let ownerTokenIdentifier: String?
        private let exerciseEntries: [ExerciseEntry]
        private let completedSessionCount: Int
        private let latestCompletedUpdatedAt: Date?
        // Sync applies remote set/exercise records without cascading touch()
        // to the parent session, so session updatedAt alone would miss those
        // edits; a completed sync must invalidate the cache by itself.
        private let lastSyncedAt: Date?

        init(
            session: WorkoutSession,
            sessions: [WorkoutSession],
            ownerTokenIdentifier: String?,
            lastSyncedAt: Date? = nil
        ) {
            self.lastSyncedAt = lastSyncedAt
            sessionID = session.id
            sourceSessionID = session.source == .pastWorkout ? session.sourceSessionID : nil
            self.ownerTokenIdentifier = ownerTokenIdentifier
            exerciseEntries = session.sortedLoggedExercises.map { loggedExercise in
                ExerciseEntry(
                    id: loggedExercise.id,
                    routeID: ExerciseHistoryRoute(loggedExercise: loggedExercise).id,
                    sourceLoggedExerciseID: loggedExercise.sourceLoggedExerciseID,
                    setIDs: loggedExercise.sortedSets.map(\.id)
                )
            }

            let completedSessions = WorkoutSession.visibleCompletedSessions(
                from: sessions,
                ownerTokenIdentifier: ownerTokenIdentifier
            )
            completedSessionCount = completedSessions.count
            latestCompletedUpdatedAt = completedSessions.map(\.updatedAt).max()
        }
    }
}
