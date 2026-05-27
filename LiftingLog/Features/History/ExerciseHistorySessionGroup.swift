import Foundation

struct ExerciseHistorySetEntry: Identifiable {
    let loggedExercise: LoggedExercise
    let set: LoggedSet

    var id: UUID { self.set.id }
    var displaySetNumber: Int { self.set.orderIndex + 1 }
}

struct ExerciseHistoryLoggedExerciseEntry: Identifiable {
    let loggedExercise: LoggedExercise
    var setEntries: [ExerciseHistorySetEntry]

    var id: UUID { loggedExercise.id }
    var exerciseNotes: String { loggedExercise.notes }
}

struct ExerciseHistorySessionGroup: Identifiable {
    let session: WorkoutSession
    let setEntries: [ExerciseHistorySetEntry]
    let loggedExerciseEntries: [ExerciseHistoryLoggedExerciseEntry]

    init(session: WorkoutSession, setEntries: [ExerciseHistorySetEntry]) {
        self.session = session
        self.setEntries = setEntries
        self.loggedExerciseEntries = Self.groupByLoggedExercise(setEntries)
    }

    var id: UUID { session.id }
    var title: String { session.title }
    var startedAt: Date { session.startedAt }
    var completedSetCount: Int { setEntries.count }
    var exerciseNotes: String? {
        let notes = setEntries
            .map(\.loggedExercise)
            .first?
            .notes
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return notes.isEmpty ? nil : notes
    }

    static func makeGroups(
        from sessions: [WorkoutSession],
        matching summary: ExerciseHistorySummary
    ) -> [ExerciseHistorySessionGroup] {
        WorkoutSession.visibleCompletedSessions(from: sessions)
            .compactMap { session in
                let entries = session.sortedLoggedExercises.flatMap { loggedExercise in
                    guard matches(loggedExercise, summary: summary) else { return [ExerciseHistorySetEntry]() }

                    return loggedExercise.sortedSets
                        .filter(\.isCompleted)
                        .map { ExerciseHistorySetEntry(loggedExercise: loggedExercise, set: $0) }
                }

                guard !entries.isEmpty else { return nil }
                return ExerciseHistorySessionGroup(session: session, setEntries: entries)
            }
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.title < rhs.title
                }
                return lhs.startedAt > rhs.startedAt
            }
    }

    static func recentGroups(
        from sessions: [WorkoutSession],
        matching summary: ExerciseHistorySummary,
        limit: Int = 3
    ) -> [ExerciseHistorySessionGroup] {
        Array(makeGroups(from: sessions, matching: summary).prefix(limit))
    }

    private static func matches(_ loggedExercise: LoggedExercise, summary: ExerciseHistorySummary) -> Bool {
        if let exerciseID = summary.exerciseID {
            return loggedExercise.exercise?.id == exerciseID
        }

        return loggedExercise.exerciseSnapshotName.caseInsensitiveCompare(summary.name) == .orderedSame
    }

    private static func groupByLoggedExercise(
        _ setEntries: [ExerciseHistorySetEntry]
    ) -> [ExerciseHistoryLoggedExerciseEntry] {
        var groupedEntries: [ExerciseHistoryLoggedExerciseEntry] = []
        var groupedIndexByLoggedExerciseID: [UUID: Int] = [:]

        for setEntry in setEntries {
            let loggedExerciseID = setEntry.loggedExercise.id

            if let groupedIndex = groupedIndexByLoggedExerciseID[loggedExerciseID] {
                groupedEntries[groupedIndex].setEntries.append(setEntry)
            } else {
                groupedIndexByLoggedExerciseID[loggedExerciseID] = groupedEntries.count
                groupedEntries.append(
                    ExerciseHistoryLoggedExerciseEntry(
                        loggedExercise: setEntry.loggedExercise,
                        setEntries: [setEntry]
                    )
                )
            }
        }

        return groupedEntries
    }
}
