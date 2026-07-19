import Foundation

enum MeasurementUnit: String, CaseIterable, Codable, Identifiable {
    case pounds
    case kilograms

    private static let poundsPerKilogram = 2.20462262185
    static let canonicalWeightUnit: MeasurementUnit = .pounds

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
            return "LBS"
        case .kilograms:
            return "KG"
        }
    }

    func convert(_ weight: Double, to targetUnit: MeasurementUnit) -> Double {
        guard self != targetUnit else { return weight }

        switch (self, targetUnit) {
        case (.pounds, .kilograms):
            return weight / Self.poundsPerKilogram
        case (.kilograms, .pounds):
            return weight * Self.poundsPerKilogram
        case (.pounds, .pounds), (.kilograms, .kilograms):
            return weight
        }
    }

    func displayWeight(fromCanonicalPounds canonicalPounds: Double?) -> Double? {
        canonicalPounds.map { Self.canonicalWeightUnit.convert($0, to: self) }
    }

    func canonicalWeight(fromDisplayWeight displayWeight: Double?) -> Double? {
        displayWeight.map { self.convert($0, to: Self.canonicalWeightUnit) }
    }
}
