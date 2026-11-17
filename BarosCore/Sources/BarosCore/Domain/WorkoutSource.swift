import Foundation

public enum WorkoutSource: String, CaseIterable, Codable, Identifiable {
    case blank
    case pastWorkout
    case template

    public var id: String { rawValue }
}
