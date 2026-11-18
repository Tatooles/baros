import Foundation

public enum WorkoutField: Hashable {
    case workoutTitle
    case workoutNotes
    case exerciseNotes(UUID)
    case setWeight(UUID)
    /// The set's measure field: reps, or time for a timed exercise.
    case setReps(UUID)
}
