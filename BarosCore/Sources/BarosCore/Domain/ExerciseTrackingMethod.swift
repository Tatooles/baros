import Foundation

/// What an exercise's sets measure. Weight is optional either way.
public enum ExerciseTrackingMethod: String, CaseIterable, Identifiable, Sendable {
    case reps
    case duration

    public var id: String { rawValue }

    /// Missing or unrecognized stored values are rep-based: every exercise and
    /// workout from before timed exercises, and any method a newer build adds.
    init(storedRawValue: String?) {
        self = storedRawValue.flatMap(Self.init(rawValue:)) ?? .reps
    }

    public var displayName: String {
        switch self {
        case .reps: "Reps"
        case .duration: "Time"
        }
    }

    /// The set column header and empty-field placeholder.
    public var fieldLabel: String {
        switch self {
        case .reps: "REPS"
        case .duration: "TIME"
        }
    }
}
