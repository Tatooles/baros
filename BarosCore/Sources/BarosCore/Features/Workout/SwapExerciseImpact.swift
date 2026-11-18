import Foundation

/// The exercise a swap replaces, and what replacing it throws away.
/// The swap picker states this above its confirm button instead of asking again in an alert.
public struct SwapExerciseImpact {
    public let originalExerciseID: UUID?
    public let originalName: String
    let muscleGroup: ExerciseMuscleGroup?
    /// Counted the way Edit Workout counts them: completed, or holding a weight or reps.
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

    /// "Removes 2 logged sets and the exercise note from Bench Press", or that nothing is logged yet.
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

    /// Names the equipment when the replacement shares the original's name, so variants stay distinguishable.
    public func confirmTitle(for replacement: Exercise) -> String {
        let sharesName = originalName.localizedCaseInsensitiveCompare(replacement.name) == .orderedSame
        let name = sharesName ? "\(replacement.name) (\(replacement.equipment.displayName))" : replacement.name
        return "Swap for \(name)"
    }

    /// Exercises already performed that train the same muscle group, most recent first.
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
