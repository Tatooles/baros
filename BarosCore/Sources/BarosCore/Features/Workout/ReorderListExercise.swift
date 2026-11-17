import Foundation

/// What one exercise row in `ReorderExercisesList` shows.
public protocol ReorderListExercise: Identifiable where ID == UUID {
    var name: String { get }
    var metadata: String? { get }
    var supersetGroupID: UUID? { get }
    /// Shown at the end of the detail line, such as set progress.
    var trailingDetail: String? { get }
    var isNew: Bool { get }
    var accessibilityValue: String { get }
}

extension WorkoutExerciseListSnapshot.ExerciseState: ReorderListExercise {
    public var trailingDetail: String? { progressText }
}
