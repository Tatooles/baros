import Foundation
import SwiftData

/// A named, ordered list of exercises to start a workout from. Workouts never
/// change their template; only editing the template does.
@Model
final class WorkoutTemplate: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Replace the whole array to change it; SwiftData doesn't see in-place edits.
    var entries: [WorkoutTemplateEntry] = []
    var syncOwnerTokenIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        entries: [WorkoutTemplateEntry] = [],
        syncOwnerTokenIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.syncOwnerTokenIdentifier = syncOwnerTokenIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    func isVisible(to ownerTokenIdentifier: String?) -> Bool {
        syncOwnerTokenIdentifier == ownerTokenIdentifier
    }

    /// Points entries for one library exercise at another, for when sync
    /// replaces an exercise's id or folds a duplicate into it. Returns whether
    /// any entry changed.
    func repointEntries(from oldExerciseID: UUID, to newExerciseID: UUID) -> Bool {
        guard entries.contains(where: { $0.exerciseID == oldExerciseID }) else { return false }
        entries = entries.map { entry in
            var entry = entry
            if entry.exerciseID == oldExerciseID { entry.exerciseID = newExerciseID }
            return entry
        }
        return true
    }
}

/// One exercise in a template. The snapshot keeps the exercise showing by
/// name after its library exercise is deleted.
struct WorkoutTemplateEntry: Codable, Hashable, Identifiable {
    var id: UUID
    /// The library exercise. Looked up by id rather than held as a
    /// relationship so an entry pulled before its exercise still resolves.
    var exerciseID: UUID?
    var exerciseSnapshotName: String
    var exerciseSnapshotEquipmentRaw: String
    var exerciseSnapshotPrimaryMuscleGroupRaw: String
    /// Shared by neighboring entries in a superset. See `SupersetGrouping`.
    var supersetGroupID: UUID?

    init(
        id: UUID = UUID(),
        exerciseID: UUID?,
        exerciseSnapshotName: String,
        exerciseSnapshotEquipmentRaw: String,
        exerciseSnapshotPrimaryMuscleGroupRaw: String,
        supersetGroupID: UUID? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseSnapshotName = exerciseSnapshotName
        self.exerciseSnapshotEquipmentRaw = exerciseSnapshotEquipmentRaw
        self.exerciseSnapshotPrimaryMuscleGroupRaw = exerciseSnapshotPrimaryMuscleGroupRaw
        self.supersetGroupID = supersetGroupID
    }

    init(exercise: Exercise, supersetGroupID: UUID? = nil) {
        self.init(
            exerciseID: exercise.id,
            exerciseSnapshotName: exercise.name,
            exerciseSnapshotEquipmentRaw: exercise.equipmentRaw,
            exerciseSnapshotPrimaryMuscleGroupRaw: exercise.primaryMuscleGroupRaw,
            supersetGroupID: supersetGroupID
        )
    }
}
