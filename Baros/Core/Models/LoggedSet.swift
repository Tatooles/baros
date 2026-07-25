import Foundation
import SwiftData

@Model
final class LoggedSet: Identifiable {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var weight: Double?
    var reps: Int?
    var rpe: Double?
    var kindRaw: String
    var isCompleted: Bool
    var completedAt: Date?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var healthLinkID: UUID?
    var sourceLoggedSetID: UUID?
    var loggedExercise: LoggedExercise?

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        weight: Double? = nil,
        reps: Int? = nil,
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

    var isDeleted: Bool {
        deletedAt != nil
    }

    func touch(now: Date = .now) {
        updatedAt = now
        loggedExercise?.touch(now: now)
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
