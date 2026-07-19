import Foundation

enum ExerciseCategory: String, CaseIterable, Codable, Identifiable {
    case strength
    case cardio
    case mobility
    case other

    var id: String { rawValue }

    var displayName: String {
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
