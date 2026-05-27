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
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        weightUnit: MeasurementUnit = .pounds,
        defaultRestTimerSeconds: Int = 90,
        hasCompletedOnboarding: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.weightUnitRaw = weightUnit.rawValue
        self.defaultRestTimerSeconds = defaultRestTimerSeconds
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    static func visibleSettingsRecords(from settingsRecords: [UserSettings]) -> [UserSettings] {
        settingsRecords.filter { !$0.isDeleted }
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
        for set in sets where !set.isDeleted {
            var didConvertSet = false
            if let weight = set.weight {
                set.weight = previousUnit.convert(weight, to: newUnit)
                didConvertSet = true
            }
            if let placeholderWeight = set.placeholderWeight {
                set.placeholderWeight = previousUnit.convert(placeholderWeight, to: newUnit)
                didConvertSet = true
            }
            if didConvertSet {
                set.touch()
            }
        }

        weightUnit = newUnit
        try context.save()
    }

    func touch(now: Date = .now) {
        updatedAt = now
    }

    func markDeleted(now: Date = .now) {
        deletedAt = now
        updatedAt = now
    }

    func restoreFromDeletion(now: Date = .now) {
        deletedAt = nil
        updatedAt = now
    }
}
