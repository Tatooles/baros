import Foundation
import SwiftData

enum ExerciseRemovalOutcome {
    case archived
    case deleted
}

@Model
final class Exercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var seedIdentifier: String?
    var name: String
    var categoryRaw: String
    var equipmentRaw: String
    var primaryMuscleRaw: String = ""
    var primaryMuscleGroupRaw: String = ExerciseMuscleGroup.other.rawValue
    var notes: String
    var isArchived: Bool
    var isSeeded: Bool
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
        notes: String = "",
        isArchived: Bool = false,
        isSeeded: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.seedIdentifier = seedIdentifier
        self.name = name
        self.categoryRaw = category.rawValue
        self.equipmentRaw = equipment.rawValue
        self.primaryMuscleRaw = primaryMuscleGroup.displayName
        self.primaryMuscleGroupRaw = primaryMuscleGroup.rawValue
        self.notes = notes
        self.isArchived = isArchived
        self.isSeeded = isSeeded
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
        notes: String = "",
        isArchived: Bool = false,
        isSeeded: Bool = false,
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
            notes: notes,
            isArchived: isArchived,
            isSeeded: isSeeded,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
        self.primaryMuscleRaw = primaryMuscle
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    static func visibleActiveExercises(from exercises: [Exercise]) -> [Exercise] {
        exercises.filter { !$0.isArchived && !$0.isDeleted }
    }

    var category: ExerciseCategory {
        get { ExerciseCategory(rawValue: categoryRaw) ?? .other }
        set {
            categoryRaw = newValue.rawValue
            touch()
        }
    }

    var equipment: ExerciseEquipment {
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

    var primaryMuscleGroup: ExerciseMuscleGroup {
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

    var metadataDisplayText: String {
        "\(equipment.displayName) • \(primaryMuscleGroup.displayName)"
    }

    func hasSameActiveIdentity(name normalizedName: String, equipment candidateEquipment: ExerciseEquipment) -> Bool {
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

    @discardableResult
    func archiveOrDelete(context: ModelContext, now: Date = .now) throws -> ExerciseRemovalOutcome {
        let exerciseID = id
        let hasLoggedHistory = try context.fetch(FetchDescriptor<LoggedExercise>())
            .contains { $0.exercise?.id == exerciseID }

        if isSeeded || hasLoggedHistory {
            archive(now: now)
            return .archived
        } else {
            markDeleted(now: now)
            return .deleted
        }
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
