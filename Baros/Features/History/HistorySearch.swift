import Foundation

enum HistorySearch {
    static func hasQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func workouts(
        in sessions: [WorkoutSession],
        matching query: String
    ) -> [WorkoutSession] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return sessions
        }

        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(normalizedQuery)
                || session.sortedLoggedExercises.contains { loggedExercise in
                    loggedExercise.exerciseSnapshotName.localizedCaseInsensitiveContains(normalizedQuery)
                }
        }
    }

    static func exercises(
        in summaries: [ExerciseHistorySummary],
        matching query: String
    ) -> [ExerciseHistorySummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return summaries
        }

        return summaries.filter { summary in
            summary.name.localizedCaseInsensitiveContains(normalizedQuery)
                || summary.metadataDisplayText?.localizedCaseInsensitiveContains(normalizedQuery) == true
        }
    }
}
