import Foundation

public final class WorkoutHistorySearchIndex {
    private let indexedSessions: [WorkoutSession]
    private lazy var searchableFieldsBySessionID: [UUID: [String]] = Dictionary(
        uniqueKeysWithValues: indexedSessions.map { session in
            (
                session.id,
                [session.title] + session.sortedLoggedExercises.map(\.exerciseSnapshotName)
            )
        }
    )

    public init(sessions: [WorkoutSession]) {
        indexedSessions = sessions
    }

    public func prepare() {
        _ = searchableFieldsBySessionID
    }

    public func sessions(
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

public enum HistorySearch {
    public static func hasQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func exercises(
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
