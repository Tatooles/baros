import Foundation

public struct HomePrimaryWorkoutPresentation: Equatable {
    public let title: String
    public let detail: String?
    public let accessibilityIdentifier: String
    public let isActive: Bool

    public init(
        activeSession: WorkoutSession?,
        sessionIDHiddenDuringLaunchHandoff: UUID? = nil,
        now: Date
    ) {
        guard let activeSession,
              activeSession.id != sessionIDHiddenDuringLaunchHandoff else {
            title = "Start Workout"
            detail = nil
            accessibilityIdentifier = "StartWorkoutButton"
            isActive = false
            return
        }

        title = "Return to Workout"
        detail = "\(activeSession.title) · "
            + WorkoutFormatters.homeElapsedDescription(activeSession.effectiveDurationSeconds(now: now))
        accessibilityIdentifier = "ReturnToActiveWorkoutButton"
        isActive = true
    }
}

public struct HomePastWorkoutReviewPresentation: Equatable {
    public struct Exercise: Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let equipment: String?
        let copiedSetCount: Int
        public var supersetGroupID: UUID?

        public var copiedSetDescription: String {
            "\(copiedSetCount) \(copiedSetCount == 1 ? "set" : "sets")"
        }
    }

    public let completedAt: Date
    let copiedSetCount: Int
    public let exercises: [Exercise]

    public var structureSummary: String {
        let exerciseLabel = exercises.count == 1 ? "exercise" : "exercises"
        let setLabel = copiedSetCount == 1 ? "set" : "sets"
        return "\(exercises.count) \(exerciseLabel) · \(copiedSetCount) \(setLabel)"
    }

    public init(session: WorkoutSession, sessions: [WorkoutSession], ownerTokenIdentifier: String?) {
        let newerSetKinds = PreviousSetPerformance.newerCompletedSetKindsByExerciseID(
            for: session,
            in: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        completedAt = session.endedAt ?? session.startedAt
        exercises = session.sortedLoggedExercises.map { loggedExercise in
            Exercise(
                id: loggedExercise.id,
                name: loggedExercise.exerciseSnapshotName,
                equipment: loggedExercise.snapshotEquipment?.displayName,
                copiedSetCount: newerSetKinds[loggedExercise.id]?.count ?? loggedExercise.sortedSets.count,
                supersetGroupID: loggedExercise.supersetGroupID
            )
        }
        copiedSetCount = exercises.reduce(0) { $0 + $1.copiedSetCount }
    }
}

public struct HomeContent {
    public let completedSessions: [WorkoutSession]
    private let pastSessions: [WorkoutSession]

    public init(
        sessions: [WorkoutSession],
        ownerTokenIdentifier: String?,
        now: Date = .now
    ) {
        completedSessions = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        pastSessions = completedSessions.filter { session in
            (session.endedAt ?? session.startedAt) <= now
        }
    }

    public var quickStartWorkouts: [HomeQuickStartWorkout] {
        HomeQuickStartWorkout.workouts(from: pastSessions)
    }

    public func pastWorkouts(matching query: String) -> [WorkoutSession] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return completedSessions
        }

        return completedSessions.filter { session in
            session.title.localizedCaseInsensitiveContains(normalizedQuery)
                || session.sortedLoggedExercises.contains { loggedExercise in
                    loggedExercise.exerciseSnapshotName.localizedCaseInsensitiveContains(normalizedQuery)
                }
        }
    }
}

public struct HomeQuickStartWorkout: Identifiable {
    static let maximumCount = 5
    static let maximumScannedSessionCount = 50

    let session: WorkoutSession

    public var id: UUID { session.id }

    public var name: String {
        guard Self.titleGroupingKey(session.title) == nil else { return session.title }
        let loggedExercises = session.sortedLoggedExercises
        var counts: [ExerciseMuscleGroup: Int] = [:]
        var groups: [ExerciseMuscleGroup] = []
        for loggedExercise in loggedExercises {
            guard let raw = loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw,
                  let group = ExerciseMuscleGroup(rawValue: raw), group != .other else { continue }
            if counts[group] == nil { groups.append(group) }
            counts[group, default: 0] += 1
        }
        let topGroups = groups.enumerated()
            .sorted { lhs, rhs in
                let (lhsCount, rhsCount) = (counts[lhs.element, default: 0], counts[rhs.element, default: 0])
                return lhsCount != rhsCount ? lhsCount > rhsCount : lhs.offset < rhs.offset
            }
            .prefix(2)
            .map(\.element.displayName)
        guard topGroups.isEmpty else { return topGroups.joined(separator: " · ") }
        return loggedExercises.first?.exerciseSnapshotName ?? session.title
    }

    public func lastDoneText(now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: session.startedAt), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        default:
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .locale(calendar.locale ?? .current)
            let sameYear = calendar.isDate(session.startedAt, equalTo: now, toGranularity: .year)
            return session.startedAt.formatted(sameYear ? style.month(.abbreviated).day()
                                                        : style.month(.abbreviated).day().year())
        }
    }

    static func workouts(
        from completedSessions: [WorkoutSession]
    ) -> [HomeQuickStartWorkout] {
        var seenKeys = Set<String>()
        var workouts: [HomeQuickStartWorkout] = []
        for session in completedSessions.prefix(maximumScannedSessionCount) where workouts.count < maximumCount {
            let titleKey = titleGroupingKey(session.title)
            if let titleKey, seenKeys.contains(titleKey) {
                continue
            }
            let loggedExercises = session.sortedLoggedExercises
            guard !loggedExercises.isEmpty,
                  seenKeys.insert(titleKey ?? exercisesGroupingKey(loggedExercises)).inserted else {
                continue
            }
            workouts.append(HomeQuickStartWorkout(session: session))
        }
        return workouts
    }

    private static func titleGroupingKey(_ title: String) -> String? {
        let normalizedTitle = normalized(title)
        guard normalizedTitle != normalized(WorkoutSession.defaultTitle) else {
            return nil
        }
        return "title:\(normalizedTitle)"
    }

    private static func exercisesGroupingKey(_ loggedExercises: [LoggedExercise]) -> String {
        return "exercises:" + loggedExercises.map { loggedExercise in
            "\(normalized(loggedExercise.exerciseSnapshotName))|\(loggedExercise.resolvedSnapshotEquipmentRaw ?? "")"
        }.joined(separator: "\u{1F}")
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

}
