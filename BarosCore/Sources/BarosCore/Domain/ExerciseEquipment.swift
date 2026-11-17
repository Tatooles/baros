import Foundation

public enum ExerciseEquipment: String, CaseIterable, Codable, Identifiable, Sendable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case kettlebell
    case smithMachine
    case resistanceBand
    case medicineBall
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .smithMachine: return "Smith Machine"
        case .resistanceBand: return "Resistance Band"
        case .medicineBall: return "Medicine Ball"
        case .other: return "Other"
        }
    }
}
