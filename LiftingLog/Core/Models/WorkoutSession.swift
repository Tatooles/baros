import Foundation
import SwiftData

@Model
final class WorkoutSession: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var notes: String
    var referenceNotes: String?
    var statusRaw: String
    var sourceRaw: String
    var sourceSessionID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var healthLinkID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \LoggedExercise.session) var loggedExercises: [LoggedExercise]

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Int = 0,
        notes: String = "",
        status: WorkoutSessionStatus,
        source: WorkoutSource,
        sourceSessionID: UUID? = nil,
        referenceNotes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        healthLinkID: UUID? = nil,
        loggedExercises: [LoggedExercise] = []
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.referenceNotes = referenceNotes
        self.statusRaw = status.rawValue
        self.sourceRaw = source.rawValue
        self.sourceSessionID = sourceSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.healthLinkID = healthLinkID
        self.loggedExercises = loggedExercises

        for loggedExercise in loggedExercises {
            loggedExercise.session = self
        }
    }

    var status: WorkoutSessionStatus {
        get { WorkoutSessionStatus(rawValue: statusRaw) ?? .discarded }
        set {
            statusRaw = newValue.rawValue
            touch()
        }
    }

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .blank }
        set {
            sourceRaw = newValue.rawValue
            touch()
        }
    }

    var sortedLoggedExercises: [LoggedExercise] {
        loggedExercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    func effectiveDurationSeconds(now: Date = .now) -> Int {
        if status == .active {
            return max(0, Int(now.timeIntervalSince(startedAt)))
        }

        if durationSeconds > 0 {
            return durationSeconds
        }

        if let endedAt {
            return max(0, Int(endedAt.timeIntervalSince(startedAt)))
        }

        return 0
    }

    func touch(now: Date = .now) {
        updatedAt = now
    }
}
