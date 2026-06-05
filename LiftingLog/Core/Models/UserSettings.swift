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

    @MainActor
    func updateWeightUnit(_ newUnit: MeasurementUnit, context: ModelContext) throws {
        try SettingsMutationService().updateWeightUnit(newUnit, settings: self, context: context)
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
