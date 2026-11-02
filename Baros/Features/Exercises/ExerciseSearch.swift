import Foundation

/// A small, shared matcher. Every query word must occur in a searchable field.
struct ExerciseSearch {
    private let words: [String]

    init(query: String) {
        words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Name-only matches stay ahead of matches that need equipment or target area.
    /// Empty queries match everything, preserving the caller's normal sort order.
    func rank(for exercise: Exercise) -> Int? {
        if words.allSatisfy({ exercise.name.localizedCaseInsensitiveContains($0) }) {
            return 0
        }
        let fields = [
            exercise.name,
            exercise.equipment.displayName,
            exercise.primaryMuscleGroup.displayName,
        ]
        return words.allSatisfy { word in
            fields.contains { $0.localizedCaseInsensitiveContains(word) }
        } ? 1 : nil
    }
}
