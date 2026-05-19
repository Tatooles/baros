import Foundation

enum MeasurementUnit: String, CaseIterable, Codable, Identifiable {
    case pounds
    case kilograms

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pounds:
            return "Pounds"
        case .kilograms:
            return "Kilograms"
        }
    }

    var fieldLabel: String {
        switch self {
        case .pounds:
            return "LBS"
        case .kilograms:
            return "KG"
        }
    }

    var fieldPlaceholder: String {
        switch self {
        case .pounds:
            return "lbs"
        case .kilograms:
            return "kg"
        }
    }
}
