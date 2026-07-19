import Foundation

enum WorkoutSource: String, CaseIterable, Codable, Identifiable {
    case blank
    case pastWorkout
    case template

    var id: String { rawValue }
}
