import Foundation

public struct ExerciseSearch {
    private let words: [String]

    public init(query: String) {
        words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public func rank(for exercise: Exercise) -> Int? {
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
