import Foundation
import SwiftData

@Model
final class LoggedExercise: Identifiable {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var exerciseSnapshotName: String
    var notes: String
    var referenceNotes: String?
    var createdAt: Date
    var updatedAt: Date
    var exercise: Exercise?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.loggedExercise) var sets: [LoggedSet]

    init(
        id: UUID = UUID(),
        orderIndex: Int,
        exercise: Exercise? = nil,
        exerciseSnapshotName: String? = nil,
        notes: String = "",
        referenceNotes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sets: [LoggedSet] = []
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.exercise = exercise
        self.exerciseSnapshotName = exerciseSnapshotName ?? exercise?.name ?? "Exercise"
        self.notes = notes
        self.referenceNotes = referenceNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sets = sets

        for set in sets {
            set.loggedExercise = self
        }
    }

    var sortedSets: [LoggedSet] {
        sets.sorted { $0.orderIndex < $1.orderIndex }
    }

    func touch(now: Date = .now) {
        updatedAt = now
        session?.touch(now: now)
    }
}
