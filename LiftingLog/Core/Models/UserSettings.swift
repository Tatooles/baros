import Foundation
import SwiftData

@Model
final class UserSettings: Identifiable {
    @Attribute(.unique) var id: UUID
    var weightUnitRaw: String
    var defaultRestTimerSeconds: Int
    var hasCompletedOnboarding: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        weightUnit: MeasurementUnit = .pounds,
        defaultRestTimerSeconds: Int = 90,
        hasCompletedOnboarding: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.weightUnitRaw = weightUnit.rawValue
        self.defaultRestTimerSeconds = defaultRestTimerSeconds
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var weightUnit: MeasurementUnit {
        get { MeasurementUnit(rawValue: weightUnitRaw) ?? .pounds }
        set {
            weightUnitRaw = newValue.rawValue
            touch()
        }
    }

    func updateWeightUnit(_ newUnit: MeasurementUnit, context: ModelContext) throws {
        let previousUnit = weightUnit
        guard previousUnit != newUnit else { return }

        let sets = try context.fetch(FetchDescriptor<LoggedSet>())
        for set in sets {
            guard let weight = set.weight else { continue }
            set.weight = previousUnit.convert(weight, to: newUnit)
            set.touch()
        }

        weightUnit = newUnit
        try context.save()
    }

    func touch(now: Date = .now) {
        updatedAt = now
    }
}
