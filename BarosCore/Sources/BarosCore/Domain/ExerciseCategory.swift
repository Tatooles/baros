import Foundation

public enum ExerciseCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case strength
    case cardio
    case mobility
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength:
            return "Strength"
        case .cardio:
            return "Cardio"
        case .mobility:
            return "Mobility"
        case .other:
            return "Other"
        }
    }
}
