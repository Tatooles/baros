import Foundation
import SwiftData

@Model
final class LoggedExercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var exerciseSnapshotName: String
    var exerciseSnapshotEquipmentRaw: String = ExerciseEquipment.other.rawValue
    var exerciseSnapshotPrimaryMuscleGroupRaw: String = ExerciseMuscleGroup.other.rawValue
    var hasSnapshotMetadata: Bool = false
    var notes: String
    var referenceNotes: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var exercise: Exercise?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.loggedExercise) var sets: [LoggedSet]

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        exercise: Exercise? = nil,
        exerciseSnapshotName: String? = nil,
        exerciseSnapshotEquipmentRaw: String? = nil,
        exerciseSnapshotPrimaryMuscleGroupRaw: String? = nil,
        notes: String = "",
        referenceNotes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        sets: [LoggedSet] = []
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.exerciseSnapshotName = exerciseSnapshotName ?? exercise?.name ?? "Exercise"
        self.exerciseSnapshotEquipmentRaw = exerciseSnapshotEquipmentRaw ?? exercise?.equipmentRaw ?? ExerciseEquipment.other.rawValue
        self.exerciseSnapshotPrimaryMuscleGroupRaw = exerciseSnapshotPrimaryMuscleGroupRaw ?? exercise?.primaryMuscleGroup.rawValue ?? ExerciseMuscleGroup.other.rawValue
        self.hasSnapshotMetadata = true
        self.notes = notes
        self.referenceNotes = referenceNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sets = sets

        for set in sets {
            set.loggedExercise = self
        }
    }

    var sortedSets: [LoggedSet] {
        sets
            .filter { !$0.isDeleted }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var resolvedSnapshotEquipmentRaw: String? {
        guard !hasSnapshotMetadata else {
            return exerciseSnapshotEquipmentRaw
        }

        guard exerciseSnapshotEquipmentRaw == ExerciseEquipment.other.rawValue else {
            return exerciseSnapshotEquipmentRaw
        }

        return exercise?.equipmentRaw
    }

    var resolvedSnapshotPrimaryMuscleGroupRaw: String? {
        guard !hasSnapshotMetadata else {
            return exerciseSnapshotPrimaryMuscleGroupRaw
        }

        guard exerciseSnapshotPrimaryMuscleGroupRaw == ExerciseMuscleGroup.other.rawValue else {
            return exerciseSnapshotPrimaryMuscleGroupRaw
        }

        return exercise?.primaryMuscleGroup.rawValue
    }

    var snapshotEquipment: ExerciseEquipment? {
        guard let resolvedSnapshotEquipmentRaw else { return nil }
        return ExerciseEquipment(rawValue: resolvedSnapshotEquipmentRaw) ?? .other
    }

    var snapshotPrimaryMuscleGroup: ExerciseMuscleGroup? {
        guard let resolvedSnapshotPrimaryMuscleGroupRaw else { return nil }
        return ExerciseMuscleGroup(rawValue: resolvedSnapshotPrimaryMuscleGroupRaw) ?? .other
    }

    var metadataDisplayText: String? {
        guard let snapshotEquipment, let snapshotPrimaryMuscleGroup else {
            return nil
        }

        return "\(snapshotEquipment.displayName) • \(snapshotPrimaryMuscleGroup.displayName)"
    }

    var effectiveSnapshotEquipmentRaw: String {
        resolvedSnapshotEquipmentRaw ?? ExerciseEquipment.other.rawValue
    }

    var effectiveSnapshotPrimaryMuscleGroupRaw: String {
        resolvedSnapshotPrimaryMuscleGroupRaw ?? ExerciseMuscleGroup.other.rawValue
    }

    func touch(now: Date = .now) {
        updatedAt = now
        session?.touch(now: now)
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
