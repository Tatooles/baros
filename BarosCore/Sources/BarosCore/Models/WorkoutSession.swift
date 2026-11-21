import Foundation
import SwiftData

@Model
public final class WorkoutSession: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    public var notes: String
    var referenceNotes: String?
    public var statusRaw: String
    var sourceRaw: String
    public var sourceSessionID: UUID?
    var sourceTemplateID: UUID? = nil
    var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    var healthLinkID: UUID?
    public var syncOwnerTokenIdentifier: String? = nil
    @Relationship(deleteRule: .cascade, inverse: \LoggedExercise.session) public var loggedExercises: [LoggedExercise]

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
        sourceTemplateID: UUID? = nil,
        referenceNotes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        healthLinkID: UUID? = nil,
        syncOwnerTokenIdentifier: String? = nil,
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
        self.sourceTemplateID = sourceTemplateID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.healthLinkID = healthLinkID
        self.syncOwnerTokenIdentifier = syncOwnerTokenIdentifier
        self.loggedExercises = loggedExercises

        for loggedExercise in loggedExercises {
            loggedExercise.session = self
        }
    }

    public var status: WorkoutSessionStatus {
        get { WorkoutSessionStatus(rawValue: statusRaw) ?? .discarded }
        set {
            statusRaw = newValue.rawValue
            touch()
        }
    }

    public var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .blank }
        set {
            sourceRaw = newValue.rawValue
            touch()
        }
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }

    public static let defaultTitle = "Workout"

    public var sortedLoggedExercises: [LoggedExercise] {
        loggedExercises
            .filter { $0.deletedAt == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    public var visibleExerciseCount: Int {
        sortedLoggedExercises.count
    }

    public static func visibleCompletedSessions(
        from sessions: [WorkoutSession],
        ownerTokenIdentifier: String? = nil
    ) -> [WorkoutSession] {
        let visibleCompleted = sessions.filter { session in
            session.status == .completed && !session.isDeleted
        }
        guard let ownerTokenIdentifier else {
            return visibleCompleted.filter { session in
                session.syncOwnerTokenIdentifier == nil
            }
        }

        return visibleCompleted.filter { session in
            session.syncOwnerTokenIdentifier == ownerTokenIdentifier || session.syncOwnerTokenIdentifier == nil
        }
    }

    public static func visibleActiveSessions(
        from sessions: [WorkoutSession],
        ownerTokenIdentifier: String? = nil
    ) -> [WorkoutSession] {
        sessions.filter { session in
            session.status == .active
                && !session.isDeleted
                && (
                    session.syncOwnerTokenIdentifier == ownerTokenIdentifier
                        || (ownerTokenIdentifier != nil && session.syncOwnerTokenIdentifier == nil)
                )
        }
    }

    public func allowsHistoryMutation(ownerTokenIdentifier: String?) -> Bool {
        guard let syncOwnerTokenIdentifier else {
            return true
        }

        return ownerTokenIdentifier == syncOwnerTokenIdentifier
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

    public func touch(now: Date = .now) {
        updatedAt = now
    }

    func markDeleted(now: Date = .now) {
        deletedAt = now
        updatedAt = now
    }

    func markDeletedCascade(now: Date = .now) {
        markDeleted(now: now)
        for loggedExercise in loggedExercises {
            loggedExercise.markDeleted(now: now)
            for set in loggedExercise.sets {
                set.markDeleted(now: now)
            }
        }
    }

    func restoreFromDeletion(now: Date = .now) {
        deletedAt = nil
        updatedAt = now
    }
}
