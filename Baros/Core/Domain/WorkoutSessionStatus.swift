import Foundation

enum WorkoutSessionStatus: String, CaseIterable, Codable, Identifiable {
    case active
    case completed
    case discarded

    var id: String { rawValue }
}
