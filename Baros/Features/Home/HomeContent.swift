import Foundation

struct HomePrimaryWorkoutPresentation: Equatable {
    let title: String
    let detail: String?
    let accessibilityIdentifier: String
    let isActive: Bool

    init(
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

struct HomePastWorkoutReviewPresentation: Equatable {
    struct Exercise: Equatable, Identifiable {
        let id: UUID
        let name: String
        let equipment: String?
        let copiedSetCount: Int

        var copiedSetDescription: String {
            "\(copiedSetCount) \(copiedSetCount == 1 ? "set" : "sets")"
        }
    }

    let completedAt: Date
    let copiedSetCount: Int
    let exercises: [Exercise]

    var structureSummary: String {
        let exerciseLabel = exercises.count == 1 ? "exercise" : "exercises"
        let setLabel = copiedSetCount == 1 ? "set" : "sets"
        return "\(exercises.count) \(exerciseLabel) · \(copiedSetCount) \(setLabel)"
    }

    init(session: WorkoutSession) {
        completedAt = session.endedAt ?? session.startedAt
        exercises = session.sortedLoggedExercises.map { loggedExercise in
            Exercise(
                id: loggedExercise.id,
                name: loggedExercise.exerciseSnapshotName,
                equipment: loggedExercise.snapshotEquipment?.displayName,
                copiedSetCount: loggedExercise.sortedSets.count
            )
        }
        copiedSetCount = exercises.reduce(0) { $0 + $1.copiedSetCount }
    }
}

struct HomeContent {
    let completedSessions: [WorkoutSession]
    let quickStartWorkouts: [HomeQuickStartWorkout]

    init(
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
        // Home reflects what has happened. Future-dated completions (imports, wrong device clocks) stay in
        // History and Use Past Workout but never mark days or read as "Today" before they occur.
        let pastSessions = completedSessions.filter { session in
            (session.endedAt ?? session.startedAt) <= now
        }
        quickStartWorkouts = HomeQuickStartWorkout.workouts(from: pastSessions)
    }

    func pastWorkouts(matching query: String) -> [WorkoutSession] {
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

/// A recent distinct completed workout that Home offers to repeat.
struct HomeQuickStartWorkout: Identifiable {
    static let maximumCount = 5

    let session: WorkoutSession

    var id: UUID { session.id }
    var title: String { session.title }

    /// Expects `completedSessions` newest start first, the same date the ring and History use. Custom titles
    /// group by title; workouts still using the default title group by their ordered exercises so unrenamed
    /// workouts stay distinguishable.
    static func workouts(
        from completedSessions: [WorkoutSession]
    ) -> [HomeQuickStartWorkout] {
        var seenKeys = Set<String>()
        var workouts: [HomeQuickStartWorkout] = []
        for session in completedSessions where workouts.count < maximumCount {
            let loggedExercises = session.sortedLoggedExercises
            guard !loggedExercises.isEmpty,
                  seenKeys.insert(groupingKey(title: session.title, loggedExercises: loggedExercises)).inserted else {
                continue
            }
            workouts.append(HomeQuickStartWorkout(session: session))
        }
        return workouts
    }

    private static func groupingKey(title: String, loggedExercises: [LoggedExercise]) -> String {
        let normalizedTitle = normalized(title)
        guard normalizedTitle == normalized(WorkoutSession.defaultTitle) else {
            return "title:\(normalizedTitle)"
        }
        // Equipment keeps same-named variants (barbell vs. cable Row) apart.
        return "exercises:" + loggedExercises.map { loggedExercise in
            "\(normalized(loggedExercise.exerciseSnapshotName))|\(loggedExercise.resolvedSnapshotEquipmentRaw ?? "")"
        }.joined(separator: "\u{1F}")
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

}
