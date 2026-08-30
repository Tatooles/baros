import Foundation

struct WorkoutHistorySearchIndex {
    private let searchableFieldsBySessionID: [UUID: [String]]

    init(sessions: [WorkoutSession]) {
        searchableFieldsBySessionID = Dictionary(
            uniqueKeysWithValues: sessions.map { session in
                (
                    session.id,
                    [session.title] + session.sortedLoggedExercises.map(\.exerciseSnapshotName)
                )
            }
        )
    }

    func sessions(
        from sessions: [WorkoutSession],
        matching query: String
    ) -> [WorkoutSession] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return sessions
        }

        return sessions.filter { session in
            searchableFieldsBySessionID[session.id]?.contains { field in
                field.localizedCaseInsensitiveContains(normalizedQuery)
            } == true
        }
    }
}

enum HistorySearch {
    static func hasQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            let metadataFields = [
                summary.equipmentRaw.map {
                    (ExerciseEquipment(rawValue: $0) ?? .other).displayName
                },
                summary.primaryMuscleGroupRaw.map {
                    (ExerciseMuscleGroup(rawValue: $0) ?? .other).displayName
                },
            ].compactMap { $0 }

            return summary.name.localizedCaseInsensitiveContains(normalizedQuery)
                || metadataFields.contains { field in
                    field.localizedCaseInsensitiveContains(normalizedQuery)
                }
        }
    }
}
