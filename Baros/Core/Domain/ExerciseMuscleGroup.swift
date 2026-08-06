import Foundation

enum ExerciseMuscleGroup: String, CaseIterable, Codable, Identifiable {
    case abductors
    case adductors
    case biceps
    case calves
    case cardio
    case chest
    case core
    case forearms
    case fullBody
    case glutes
    case hamstrings
    case lats
    case lowerBack
    case neck
    case other
    case quads
    case shoulders
    case traps
    case triceps
    case upperBack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .lats: return "Lats"
        case .upperBack: return "Upper Back"
        case .traps: return "Traps"
        case .lowerBack: return "Lower Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .abductors: return "Abductors"
        case .adductors: return "Adductors"
        case .calves: return "Calves"
        case .core: return "Core"
        case .neck: return "Neck"
        case .fullBody: return "Full Body"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }

    static func legacyGroup(for rawValue: String) -> ExerciseMuscleGroup {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "quads", "quadriceps": return .quads
        case "hamstrings": return .hamstrings
        case "glutes", "gluteals", "posterior chain": return .glutes
        case "chest", "pecs", "pectorals": return .chest
        case "back", "upper back": return .upperBack
        case "lats", "latissimus dorsi": return .lats
        case "traps", "trapezius": return .traps
        case "lower back", "spinal erectors", "erectors": return .lowerBack
        case "rear delts", "rear deltoids", "shoulders", "delts": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "forearms": return .forearms
        case "abductors", "hip abductors": return .abductors
        case "adductors", "hip adductors": return .adductors
        case "calves": return .calves
        case "core", "abs", "abdominals": return .core
        case "neck": return .neck
        case "full body", "full-body": return .fullBody
        case "cardio": return .cardio
        default: return .other
        }
    }
}
