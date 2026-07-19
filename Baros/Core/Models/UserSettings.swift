import Foundation
import SwiftData

@Model
final class UserSettings: Identifiable {
    @Attribute(.unique) var id: UUID
    var weightUnitRaw: String
    var defaultRestTimerSeconds: Int
    var hasCompletedOnboarding: Bool
    var syncOwnerTokenIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        weightUnit: MeasurementUnit = .pounds,
        defaultRestTimerSeconds: Int = 90,
        hasCompletedOnboarding: Bool = true,
        syncOwnerTokenIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.weightUnitRaw = weightUnit.rawValue
        self.defaultRestTimerSeconds = defaultRestTimerSeconds
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.syncOwnerTokenIdentifier = syncOwnerTokenIdentifier
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

    static func visibleSettingsRecords(from settingsRecords: [UserSettings], ownerTokenIdentifier: String?) -> [UserSettings] {
        visibleSettingsRecords(from: settingsRecords).filter { $0.isVisible(to: ownerTokenIdentifier) }
    }

    func isVisible(to ownerTokenIdentifier: String?) -> Bool {
        syncOwnerTokenIdentifier == ownerTokenIdentifier
    }

    var weightUnit: MeasurementUnit {
        get { MeasurementUnit(rawValue: weightUnitRaw) ?? .pounds }
        set {
            weightUnitRaw = newValue.rawValue
            touch()
        }
    }

    func updateWeightUnit(_ newUnit: MeasurementUnit, context: ModelContext) throws {
        guard weightUnit != newUnit else { return }

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
