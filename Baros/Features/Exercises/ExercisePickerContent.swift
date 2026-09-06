import Foundation

enum ExercisePickerSortOrder: String, CaseIterable, Identifiable {
    case recent
    case mostPerformed
    case name

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recent:
            "Recent"
        case .mostPerformed:
            "Most performed"
        case .name:
            "Name"
        }
    }
}

struct ExercisePickerRowContent: Identifiable {
    let exercise: Exercise
    let historySummary: ExerciseHistorySummary?

    var id: UUID { exercise.id }
    var performanceCount: Int { historySummary?.performanceCount ?? 0 }
    var lastPerformedAt: Date? { historySummary?.lastPerformedAt }
    var performanceSummaryText: String {
        historySummary?.performanceSummaryLabel ?? "Never performed"
    }
}

struct ExercisePickerCreationSuggestion: Equatable {
    let name: String

    var title: String {
        "Create new exercise “\(name)”"
    }
}

enum ExercisePickerContent {
    static func makeRows(
        exercises: [Exercise],
        sessions: [WorkoutSession],
        ownerTokenIdentifier: String?,
        query: String,
        sortOrder: ExercisePickerSortOrder
    ) -> [ExercisePickerRowContent] {
        filterAndSort(
            rows: makeBaseRows(
                exercises: exercises,
                sessions: sessions,
                ownerTokenIdentifier: ownerTokenIdentifier
            ),
            query: query,
            sortOrder: sortOrder
        )
    }

    static func makeBaseRows(
        exercises: [Exercise],
        sessions: [WorkoutSession],
        ownerTokenIdentifier: String?
    ) -> [ExercisePickerRowContent] {
        let resolvedHistory = ExerciseHistorySummary.makeResolvedHistory(
            from: sessions,
            exercises: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
        )

        return resolvedHistory.exercises.map { exercise in
            ExercisePickerRowContent(
                exercise: exercise,
                historySummary: resolvedHistory.summary(for: exercise)
            )
        }
    }

    static func filterAndSort(
        rows: [ExercisePickerRowContent],
        query: String,
        sortOrder: ExercisePickerSortOrder
    ) -> [ExercisePickerRowContent] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return rows.sorted { sorts($0, before: $1, using: sortOrder) }
        }

        return rows.compactMap { row in
            searchRank(for: row.exercise, query: normalizedQuery).map { rank in
                (row: row, rank: rank)
            }
        }
        .sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }

            return sorts(lhs.row, before: rhs.row, using: sortOrder)
        }
        .map(\.row)
    }

    static func creationSuggestion(
        for rows: [ExercisePickerRowContent],
        query: String
    ) -> ExercisePickerCreationSuggestion? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        let hasExactNameMatch = rows.contains {
            $0.exercise.name.localizedCaseInsensitiveCompare(trimmedQuery) == .orderedSame
        }
        guard !hasExactNameMatch else { return nil }

        return ExercisePickerCreationSuggestion(name: trimmedQuery)
    }

    private static func searchRank(for exercise: Exercise, query: String) -> Int? {
        if exercise.name.localizedCaseInsensitiveContains(query) {
            return 0
        }

        if exercise.equipment.displayName.localizedCaseInsensitiveContains(query)
            || exercise.primaryMuscleGroup.displayName.localizedCaseInsensitiveContains(query)
        {
            return 1
        }

        return nil
    }

    private static func sorts(
        _ lhs: ExercisePickerRowContent,
        before rhs: ExercisePickerRowContent,
        using sortOrder: ExercisePickerSortOrder
    ) -> Bool {
        switch sortOrder {
        case .recent:
            return sortsRecentFirst(lhs, rhs)
        case .mostPerformed:
            return sortsMostPerformedFirst(lhs, rhs)
        case .name:
            return sortsByName(lhs, rhs)
        }
    }

    private static func sortsMostPerformedFirst(
        _ lhs: ExercisePickerRowContent,
        _ rhs: ExercisePickerRowContent
    ) -> Bool {
        if lhs.performanceCount != rhs.performanceCount {
            return lhs.performanceCount > rhs.performanceCount
        }

        return sortsRecentFirst(lhs, rhs)
    }

    private static func sortsRecentFirst(
        _ lhs: ExercisePickerRowContent,
        _ rhs: ExercisePickerRowContent
    ) -> Bool {
        switch (lhs.lastPerformedAt, rhs.lastPerformedAt) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return sortsByName(lhs, rhs)
        }
    }

    private static func sortsByName(
        _ lhs: ExercisePickerRowContent,
        _ rhs: ExercisePickerRowContent
    ) -> Bool {
        let nameComparison = lhs.exercise.name.localizedStandardCompare(rhs.exercise.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        let equipmentComparison = lhs.exercise.equipment.displayName.localizedStandardCompare(
            rhs.exercise.equipment.displayName
        )
        if equipmentComparison != .orderedSame {
            return equipmentComparison == .orderedAscending
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
