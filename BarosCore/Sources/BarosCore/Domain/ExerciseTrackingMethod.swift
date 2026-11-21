import Foundation

public enum ExerciseTrackingMethod: String, CaseIterable, Identifiable, Sendable {
    case reps
    case duration

    public var id: String { rawValue }

    init(storedRawValue: String?) {
        self = storedRawValue.flatMap(Self.init(rawValue:)) ?? .reps
    }

    public var displayName: String {
        switch self {
        case .reps: "Reps"
        case .duration: "Time"
        }
    }

    public var fieldLabel: String {
        switch self {
        case .reps: "REPS"
        case .duration: "TIME"
        }
    }
}
