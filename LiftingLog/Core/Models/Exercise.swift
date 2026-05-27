import Foundation
import SwiftData

@Model
final class Exercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var seedIdentifier: String?
    var name: String
    var categoryRaw: String
    var equipmentRaw: String
    var primaryMuscleRaw: String
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
        primaryMuscle: String,
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
        self.primaryMuscleRaw = primaryMuscle
        self.notes = notes
        self.isArchived = isArchived
        self.isSeeded = isSeeded
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
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
            touch()
        }
    }

    func update(
        name: String,
        category: ExerciseCategory,
        equipment: ExerciseEquipment,
        primaryMuscle: String,
        notes: String
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.equipmentRaw = equipment.rawValue
        self.primaryMuscleRaw = primaryMuscle
        self.notes = notes
        touch()
    }

    func archive() {
        isArchived = true
        touch()
    }

    func archiveOrDelete(context: ModelContext) throws {
        let exerciseID = id
        let hasLoggedHistory = try context.fetch(FetchDescriptor<LoggedExercise>())
            .contains { $0.exercise?.id == exerciseID }

        if isSeeded || hasLoggedHistory {
            archive()
        } else {
            markDeleted()
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
