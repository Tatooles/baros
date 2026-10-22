import Foundation

/// Built on first use, not on creation: indexing reads every workout's logged
/// exercises. History prepares it when search opens, before the first keystroke.
final class WorkoutHistorySearchIndex {
    private let indexedSessions: [WorkoutSession]
    private lazy var searchableFieldsBySessionID: [UUID: [String]] = Dictionary(
        uniqueKeysWithValues: indexedSessions.map { session in
            (
                session.id,
                [session.title] + session.sortedLoggedExercises.map(\.exerciseSnapshotName)
            )
        }
    )

    init(sessions: [WorkoutSession]) {
        indexedSessions = sessions
    }

    func prepare() {
        _ = searchableFieldsBySessionID
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
