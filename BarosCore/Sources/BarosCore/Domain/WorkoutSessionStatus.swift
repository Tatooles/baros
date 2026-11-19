import Foundation

public enum WorkoutSessionStatus: String, CaseIterable, Codable, Identifiable {
    case active
    case completed
    case discarded

    public var id: String { rawValue }
}
