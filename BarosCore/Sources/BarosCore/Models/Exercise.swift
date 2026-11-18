import Foundation
import SwiftData

public enum ExerciseRemovalOutcome: Equatable {
    case archived
    case deleted
}

@Model
public final class Exercise: Identifiable {
    @Attribute(.unique) public var id: UUID
    var seedIdentifier: String?
    public var name: String
    var categoryRaw: String
    public var equipmentRaw: String
    var primaryMuscleRaw: String = ""
    var primaryMuscleGroupRaw: String = ExerciseMuscleGroup.other.rawValue
    /// Nil until someone chooses a method on a build that has timed exercises.
    /// Nil reads as reps and is left out of uploads, so an exercise this device
    /// last saw on an older build can't overwrite a choice made elsewhere.
    var trackingMethodRaw: String?
    public var notes: String
    public var isArchived: Bool
    var isSeeded: Bool
    var syncOwnerTokenIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        seedIdentifier: String? = nil,
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscleGroup: ExerciseMuscleGroup,
        trackingMethod: ExerciseTrackingMethod? = nil,
        notes: String = "",
        isArchived: Bool = false,
        isSeeded: Bool = false,
        syncOwnerTokenIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.trackingMethodRaw = trackingMethod?.rawValue
        self.seedIdentifier = seedIdentifier
        self.name = name
        self.categoryRaw = category.rawValue
        self.equipmentRaw = equipment.rawValue
        self.primaryMuscleRaw = primaryMuscleGroup.displayName
        self.primaryMuscleGroupRaw = primaryMuscleGroup.rawValue
        self.notes = notes
        self.isArchived = isArchived
        self.isSeeded = isSeeded
        self.syncOwnerTokenIdentifier = syncOwnerTokenIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    convenience init(
        id: UUID = UUID(),
        seedIdentifier: String? = nil,
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscle: String,
        trackingMethod: ExerciseTrackingMethod? = nil,
        notes: String = "",
        isArchived: Bool = false,
        isSeeded: Bool = false,
        syncOwnerTokenIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.init(
            id: id,
            seedIdentifier: seedIdentifier,
            name: name,
            category: category,
            equipment: equipment,
            primaryMuscleGroup: ExerciseMuscleGroup.legacyGroup(for: primaryMuscle),
            trackingMethod: trackingMethod,
            notes: notes,
            isArchived: isArchived,
            isSeeded: isSeeded,
            syncOwnerTokenIdentifier: syncOwnerTokenIdentifier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
        self.primaryMuscleRaw = primaryMuscle
    }

    /// Public on purpose: outside BarosCore an internal `isDeleted` is invisible, so
    /// `isDeleted` there silently means SwiftData's `PersistentModel.isDeleted`, which
    /// stays false for a soft-deleted (tombstoned) record.
    public var isDeleted: Bool {
        deletedAt != nil
    }

    public static func visibleActiveExercises(from exercises: [Exercise]) -> [Exercise] {
        exercises.filter { !$0.isArchived && !$0.isDeleted }
    }

    public static func visibleActiveExercises(from exercises: [Exercise], ownerTokenIdentifier: String?) -> [Exercise] {
        visibleActiveExercises(from: exercises).filter { $0.isVisible(to: ownerTokenIdentifier) }
    }

    public func isVisible(to ownerTokenIdentifier: String?) -> Bool {
        syncOwnerTokenIdentifier == ownerTokenIdentifier
    }

    public var category: ExerciseCategory {
        get { ExerciseCategory(rawValue: categoryRaw) ?? .other }
        set {
            categoryRaw = newValue.rawValue
            touch()
        }
    }

    public var equipment: ExerciseEquipment {
        get { ExerciseEquipment(rawValue: equipmentRaw) ?? .other }
        set {
            equipmentRaw = newValue.rawValue
            touch()
        }
    }

    var primaryMuscle: String {
        get { primaryMuscleRaw }
        set {
            primaryMuscleRaw = newValue
            primaryMuscleGroupRaw = ExerciseMuscleGroup.legacyGroup(for: newValue).rawValue
            touch()
        }
    }

    public var primaryMuscleGroup: ExerciseMuscleGroup {
        get {
            guard let storedGroup = ExerciseMuscleGroup(rawValue: primaryMuscleGroupRaw) else {
                return .other
            }
            guard storedGroup == .other else {
                return storedGroup
            }

            let legacyGroup = ExerciseMuscleGroup.legacyGroup(for: primaryMuscleRaw)
            return legacyGroup == .other ? .other : legacyGroup
        }
        set {
            primaryMuscleGroupRaw = newValue.rawValue
            primaryMuscleRaw = newValue.displayName
            touch()
        }
    }

    /// Whether new sets of this exercise record reps or time.
    public var trackingMethod: ExerciseTrackingMethod {
        get { ExerciseTrackingMethod(storedRawValue: trackingMethodRaw) }
        set {
            // Keep "never chosen" until the method really changes.
            guard newValue != trackingMethod else { return }
            trackingMethodRaw = newValue.rawValue
            touch()
        }
    }

    public var metadataDisplayText: String {
        "\(equipment.displayName) • \(primaryMuscleGroup.displayName)"
    }

    public func hasSameActiveIdentity(name normalizedName: String, equipment candidateEquipment: ExerciseEquipment) -> Bool {
        !isArchived
            && !isDeleted
            && name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(normalizedName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            && equipment == candidateEquipment
    }

    func update(
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscleGroup: ExerciseMuscleGroup,
        notes: String
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.equipmentRaw = equipment.rawValue
        self.primaryMuscleGroupRaw = primaryMuscleGroup.rawValue
        self.primaryMuscleRaw = primaryMuscleGroup.displayName
        self.notes = notes
        touch()
    }

    func update(
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscle: String,
        notes: String
    ) {
        update(
            name: name,
            category: category,
            equipment: equipment,
            primaryMuscleGroup: ExerciseMuscleGroup.legacyGroup(for: primaryMuscle),
            notes: notes
        )
        self.primaryMuscleRaw = primaryMuscle
    }

    func archive(now: Date = .now) {
        isArchived = true
        touch(now: now)
    }

    public func removalOutcome(context: ModelContext) throws -> ExerciseRemovalOutcome {
        if isSeeded { return .archived }
        let exerciseID = id
        let hasLoggedHistory = try context.fetch(FetchDescriptor<LoggedExercise>())
            .contains { $0.exercise?.id == exerciseID }
        return hasLoggedHistory ? .archived : .deleted
    }

    @discardableResult
    func archiveOrDelete(context: ModelContext, now: Date = .now) throws -> ExerciseRemovalOutcome {
        let outcome = try removalOutcome(context: context)
        switch outcome {
        case .archived: archive(now: now)
        case .deleted: markDeleted(now: now)
        }
        return outcome
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
