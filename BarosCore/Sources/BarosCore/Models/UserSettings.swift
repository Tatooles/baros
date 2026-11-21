import Foundation
import SwiftData

@Model
public final class UserSettings: Identifiable {
    @Attribute(.unique) public var id: UUID
    var weightUnitRaw: String
    public var defaultRestTimerSeconds: Int
    var hasCompletedOnboarding: Bool
    var syncOwnerTokenIdentifier: String?
    public var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    /// The server's `updatedAt` for the version this copy descends from: set
    /// when a pull applies the server's version or an upload is stored, and
    /// sent as `baseUpdatedAt`. Nil for a record never synced, and on rows
    /// saved before the field existed.
    var syncBaseUpdatedAt: Double?

    static let seededRestTimerSeconds = 90

    init(
        id: UUID = UUID(),
        weightUnit: MeasurementUnit = .pounds,
        defaultRestTimerSeconds: Int = UserSettings.seededRestTimerSeconds,
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

    public static func visibleSettingsRecords(from settingsRecords: [UserSettings]) -> [UserSettings] {
        settingsRecords.filter { !$0.isDeleted }
    }

    public static func visibleSettingsRecords(from settingsRecords: [UserSettings], ownerTokenIdentifier: String?) -> [UserSettings] {
        visibleSettingsRecords(from: settingsRecords).filter { $0.isVisible(to: ownerTokenIdentifier) }
    }

    func isVisible(to ownerTokenIdentifier: String?) -> Bool {
        syncOwnerTokenIdentifier == ownerTokenIdentifier
    }

    public var weightUnit: MeasurementUnit {
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
        stampEdit(now: now)
    }

    func markDeleted(now: Date = .now) {
        deletedAt = stampEdit(now: now)
    }

    func restoreFromDeletion(now: Date = .now) {
        deletedAt = nil
        stampEdit(now: now)
    }
}

extension UserSettings: SyncEditStamped {}
