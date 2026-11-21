import Foundation
import SwiftData

@Model
public final class LoggedSet: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    var knowsDuration: Bool?
    public var rpe: Double?
    var kindRaw: String
    public var isCompleted: Bool
    var completedAt: Date?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    public var deletedAt: Date?
    /// The server's `updatedAt` for the version this copy descends from: set
    /// when a pull applies the server's version or an upload is stored, and
    /// sent as `baseUpdatedAt`. Nil for a record never synced, and on rows
    /// saved before the field existed.
    var syncBaseUpdatedAt: Double?
    var healthLinkID: UUID?
    var sourceLoggedSetID: UUID?
    public var loggedExercise: LoggedExercise?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        rpe: Double? = nil,
        kind: SetKind = .working,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        healthLinkID: UUID? = nil,
        sourceLoggedSetID: UUID? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.knowsDuration = true
        self.rpe = rpe
        self.kindRaw = kind.rawValue
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.healthLinkID = healthLinkID
        self.sourceLoggedSetID = sourceLoggedSetID
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .working }
        set {
            kindRaw = newValue.rawValue
            touch()
        }
    }

    var completedVolume: Double {
        guard isCompleted,
              let weight = WorkoutNumericInputPolicy.validatedWeight(weight),
              let reps = WorkoutNumericInputPolicy.validatedReps(reps)
        else { return 0 }
        return weight * Double(reps)
    }

    /// Public on purpose: outside BarosCore an internal `isDeleted` is invisible, so
    /// `isDeleted` there silently means SwiftData's `PersistentModel.isDeleted`, which
    /// stays false for a soft-deleted (tombstoned) record.
    public var isDeleted: Bool {
        deletedAt != nil
    }

    public var trackingMethod: ExerciseTrackingMethod {
        loggedExercise?.trackingMethod ?? .reps
    }

    func touch(now: Date = .now) {
        stampEdit(now: now)
        loggedExercise?.touch(now: now)
    }

    func touchActiveDraft(now: Date = .now) {
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

extension LoggedSet: SyncEditStamped {}
