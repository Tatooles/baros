import Foundation

public struct PreviousSetPerformance: Equatable {
    let weight: Double?
    let reps: Int?
    var durationSeconds: Int? = nil
    var trackingMethod: ExerciseTrackingMethod = .reps

    public func displayText(weightUnit: MeasurementUnit) -> String {
        let displayWeight = weightUnit.displayWeight(
            fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(weight)
        )
        let weightText = displayWeight.map(WorkoutFormatters.number)
        if trackingMethod == .duration {
            let durationText = WorkoutNumericInputPolicy.validatedDuration(durationSeconds)
                .map(WorkoutFormatters.setDuration)
            switch (weightText, durationText) {
            case let (.some(weightText), .some(durationText)): return "\(weightText) × \(durationText)"
            case let (.none, .some(durationText)): return durationText
            case let (.some(weightText), .none): return "\(weightText) × -"
            case (.none, .none): return "—"
            }
        }
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

    public static func lastCompletedSetsByExerciseID(
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
        let latestEntriesByRouteID = latestEntriesByRouteID(
            for: loggedExercises,
            in: sortedCompletedSessions(sessions, ownerTokenIdentifier: ownerTokenIdentifier)
        )

        return Dictionary(
            uniqueKeysWithValues: loggedExercises.map { loggedExercise in
                let routeID = ExerciseHistoryRoute(loggedExercise: loggedExercise).id
                return (
                    loggedExercise.id,
                    latestEntriesByRouteID[routeID]?.sets.map {
                        makePerformance(from: $0, trackingMethod: loggedExercise.trackingMethod)
                    } ?? []
                )
            }
        )
    }

    static func lastCompletedSetKinds(
        for route: ExerciseHistoryRoute,
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?
    ) -> [SetKind] {
        latestEntriesByRouteID(
            matching: [route.id],
            in: sortedCompletedSessions(sessions, ownerTokenIdentifier: ownerTokenIdentifier)
        )[route.id]?.sets.map(\.kind) ?? []
    }

    static func newerCompletedSetKindsByExerciseID(
        for pastSession: WorkoutSession,
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?
    ) -> [UUID: [SetKind]] {
        let sortedSessions = sortedCompletedSessions(sessions, ownerTokenIdentifier: ownerTokenIdentifier)
        guard let sourceRank = sortedSessions.firstIndex(where: { $0.id == pastSession.id }) else {
            return [:]
        }

        let routeIDsByExerciseID = pastSession.sortedLoggedExercises.map {
            (exerciseID: $0.id, routeID: ExerciseHistoryRoute(loggedExercise: $0).id)
        }
        let routeCounts = Dictionary(routeIDsByExerciseID.map { ($0.routeID, 1) }, uniquingKeysWith: +)
        let newerEntriesByRouteID = latestEntriesByRouteID(
            matching: Set(routeCounts.filter { $0.value == 1 }.keys),
            in: Array(sortedSessions.prefix(sourceRank))
        )

        var result: [UUID: [SetKind]] = [:]
        for (exerciseID, routeID) in routeIDsByExerciseID {
            guard let entry = newerEntriesByRouteID[routeID] else { continue }
            result[exerciseID] = entry.sets.map(\.kind)
        }
        return result
    }

    private static func lastCompletedSetsByExerciseIDFromSourceSession(
        for loggedExercises: [LoggedExercise],
        in sessions: [WorkoutSession],
        ownerTokenIdentifier: String?,
        sourceSessionID: UUID
    ) -> [UUID: [PreviousSetPerformance]] {
        let sortedSessions = sortedCompletedSessions(sessions, ownerTokenIdentifier: ownerTokenIdentifier)
        let latestEntriesByRouteID = latestEntriesByRouteID(for: loggedExercises, in: sortedSessions)
        let sourceRank = sortedSessions.firstIndex { $0.id == sourceSessionID }
        let sourceEntriesByID = sourceRank.map { rank in
            Dictionary(
                uniqueKeysWithValues: sortedSessions[rank].sortedLoggedExercises.map { ($0.id, $0) }
            )
        } ?? [:]

        return Dictionary(
            uniqueKeysWithValues: loggedExercises.map { loggedExercise in
                let latestEntry = latestEntriesByRouteID[ExerciseHistoryRoute(loggedExercise: loggedExercise).id]

                guard let sourceRank,
                      let sourceLoggedExerciseID = loggedExercise.sourceLoggedExerciseID,
                      let sourceLoggedExercise = sourceEntriesByID[sourceLoggedExerciseID] else {
                    return (loggedExercise.id, latestEntry?.sets.map {
                        makePerformance(from: $0, trackingMethod: loggedExercise.trackingMethod)
                    } ?? [])
                }

                let previousSets: [LoggedSet]
                if let latestEntry, latestEntry.sessionRank < sourceRank {
                    previousSets = latestEntry.sets
                } else {
                    previousSets = sourceLoggedExercise.sortedSets
                }

                return (
                    loggedExercise.id,
                    alignedSetPerformances(
                        for: loggedExercise,
                        in: sourceLoggedExercise,
                        from: previousSets
                    )
                )
            }
        )
    }

    private struct LatestEntry {
        let sessionRank: Int
        let sets: [LoggedSet]
    }

    private static func sortedCompletedSessions(
        _ sessions: [WorkoutSession],
        ownerTokenIdentifier: String?
    ) -> [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        .sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func latestEntriesByRouteID(
        for loggedExercises: [LoggedExercise],
        in sortedSessions: [WorkoutSession]
    ) -> [String: LatestEntry] {
        latestEntriesByRouteID(
            matching: Set(loggedExercises.map { ExerciseHistoryRoute(loggedExercise: $0).id }),
            in: sortedSessions
        )
    }

    private static func latestEntriesByRouteID(
        matching routeIDs: Set<String>,
        in sortedSessions: [WorkoutSession]
    ) -> [String: LatestEntry] {
        guard !routeIDs.isEmpty else { return [:] }

        var result: [String: LatestEntry] = [:]

        for (rank, session) in sortedSessions.enumerated() {
            for loggedExercise in session.sortedLoggedExercises {
                let routeID = ExerciseHistoryRoute(loggedExercise: loggedExercise).id
                guard routeIDs.contains(routeID), result[routeID] == nil else { continue }

                let completedSets = loggedExercise.sortedSets.filter(\.isCompleted)
                guard !completedSets.isEmpty else { continue }

                result[routeID] = LatestEntry(sessionRank: rank, sets: completedSets)
            }

            if result.count == routeIDs.count {
                break
            }
        }

        return result
    }

    private static func alignedSetPerformances(
        for activeLoggedExercise: LoggedExercise,
        in sourceLoggedExercise: LoggedExercise,
        from previousSets: [LoggedSet]
    ) -> [PreviousSetPerformance] {
        let activeSets = activeLoggedExercise.sortedSets

        guard let lastLinkedIndex = activeSets.lastIndex(where: { $0.sourceLoggedSetID != nil }) else {
            return []
        }

        let sourcePositionsByID = Dictionary(
            uniqueKeysWithValues: sourceLoggedExercise.sortedSets.enumerated().map { ($1.id, $0) }
        )

        return activeSets.prefix(through: lastLinkedIndex).map { activeSet in
            if let sourceSetID = activeSet.sourceLoggedSetID,
               let position = sourcePositionsByID[sourceSetID],
               previousSets.indices.contains(position) {
                return makePerformance(from: previousSets[position], trackingMethod: activeLoggedExercise.trackingMethod)
            }

            return PreviousSetPerformance(weight: nil, reps: nil, trackingMethod: activeLoggedExercise.trackingMethod)
        }
    }

    private static func makePerformance(
        from set: LoggedSet,
        trackingMethod: ExerciseTrackingMethod
    ) -> PreviousSetPerformance {
        PreviousSetPerformance(
            weight: set.weight,
            reps: trackingMethod == .reps ? set.reps : nil,
            durationSeconds: trackingMethod == .duration ? set.durationSeconds : nil,
            trackingMethod: trackingMethod
        )
    }

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

enum PreviousSetsCacheReloadPolicy {
    static func shouldReload<ID: Hashable>(
        insertedIDs: Set<ID>,
        updatedIDs: Set<ID>,
        deletedIDs: Set<ID>,
        activeGraphIDs: Set<ID>,
        activeStructureChanged: Bool = false,
        invalidatedAllIdentifiers: Bool = false
    ) -> Bool {
        if invalidatedAllIdentifiers
            || activeStructureChanged
            || !insertedIDs.isEmpty
            || !deletedIDs.isEmpty {
            return true
        }

        return !updatedIDs.isSubset(of: activeGraphIDs)
    }
}

public struct PreviousSetsCacheReloadTrigger: Equatable {
    let sessionID: UUID
    public let ownerTokenIdentifier: String?
    public let lastSyncedAt: Date?

    public init(sessionID: UUID, ownerTokenIdentifier: String?, lastSyncedAt: Date?) {
        self.sessionID = sessionID
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.lastSyncedAt = lastSyncedAt
    }
}
