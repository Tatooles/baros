import Foundation

public struct SwapExerciseImpact {
    public let originalExerciseID: UUID?
    public let originalName: String
    let muscleGroup: ExerciseMuscleGroup?
    let loggedSetCount: Int
    let hasNote: Bool

    public init(original: LoggedExercise) {
        originalExerciseID = original.exercise?.id
        originalName = original.exerciseSnapshotName
        muscleGroup = original.exercise?.primaryMuscleGroup ?? original.snapshotPrimaryMuscleGroup
        loggedSetCount = WorkoutExerciseListSnapshot.ExerciseState(original).loggedSetCount
        hasNote = !original.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var losesWork: Bool { loggedSetCount > 0 || hasNote }

    public var lossMessage: String {
        let sets: String? = switch loggedSetCount {
        case 0: nil
        case 1: "1 logged set"
        case let count: "\(count) logged sets"
        }
        let parts = [sets, hasNote ? "the exercise note" : nil].compactMap { $0 }
        guard !parts.isEmpty else { return "\(originalName) has nothing logged yet" }
        return "Removes \(parts.joined(separator: " and ")) from \(originalName)"
    }

    public func confirmTitle(for replacement: Exercise) -> String {
        let sharesName = originalName.localizedCaseInsensitiveCompare(replacement.name) == .orderedSame
        let name = sharesName ? "\(replacement.name) (\(replacement.equipment.displayName))" : replacement.name
        return "Swap for \(name)"
    }

    public func similarRows(
        in rows: [ExercisePickerRowContent],
        limit: Int = 4
    ) -> [ExercisePickerRowContent] {
        guard let muscleGroup, muscleGroup != .other else { return [] }
        let candidates = rows.filter {
            $0.exercise.primaryMuscleGroup == muscleGroup
                && $0.exercise.id != originalExerciseID
                && $0.lastPerformedAt != nil
        }
        return Array(
            ExercisePickerContent.filterAndSort(rows: candidates, query: "", sortOrder: .recent).prefix(limit)
        )
    }
}
