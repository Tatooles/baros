import Foundation
import SwiftData

@Model
public final class WorkoutTemplate: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var entries: [WorkoutTemplateEntry] = []
    var syncOwnerTokenIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    /// The server's `updatedAt` for the version this copy descends from: set
    /// when a pull applies the server's version or an upload is stored, and
    /// sent as `baseUpdatedAt`. Nil for a record never synced, and on rows
    /// saved before the field existed.
    var syncBaseUpdatedAt: Double?

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

public struct WorkoutTemplateEntry: Codable, Hashable, Identifiable {
    public var id: UUID
    var exerciseID: UUID?
    var exerciseSnapshotName: String
    var exerciseSnapshotEquipmentRaw: String
    var exerciseSnapshotPrimaryMuscleGroupRaw: String
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

    public static func entries(copying session: WorkoutSession) -> [WorkoutTemplateEntry] {
        let loggedExercises = session.sortedLoggedExercises
        let groupIDs = SupersetGrouping.copied(loggedExercises.map(\.supersetGroupID))
        return zip(loggedExercises, groupIDs).map { loggedExercise, groupID in
            if let exercise = loggedExercise.exercise, !exercise.isDeleted {
                return WorkoutTemplateEntry(exercise: exercise, supersetGroupID: groupID)
            }
            return WorkoutTemplateEntry(
                exerciseID: nil,
                exerciseSnapshotName: loggedExercise.exerciseSnapshotName,
                exerciseSnapshotEquipmentRaw: loggedExercise.effectiveSnapshotEquipmentRaw,
                exerciseSnapshotPrimaryMuscleGroupRaw: loggedExercise.effectiveSnapshotPrimaryMuscleGroupRaw,
                supersetGroupID: groupID
            )
        }
    }
}

extension WorkoutTemplate: SyncEditStamped {}
