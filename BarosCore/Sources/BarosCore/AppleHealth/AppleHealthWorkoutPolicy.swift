import Foundation

public enum AppleHealthWorkoutAction: Equatable, Sendable {
    case startSession(workoutID: UUID, startedAt: Date, syncVersion: Int64)
    case finishSession(workoutID: UUID, endedAt: Date)
    case discardSession(workoutID: UUID)
    /// Offline save of a workout without a surviving live session (ADR 0005, "Fallback write").
    case saveWorkout(workoutID: UUID, startedAt: Date, endedAt: Date, syncVersion: Int64)
}

public struct AppleHealthWorkoutDecision: Equatable, Sendable {
    /// The entry to store before the action runs, so the writer is recorded before any save.
    /// `nil` means this device doesn't track the workout.
    public let entry: AppleHealthLedgerEntry?
    public let action: AppleHealthWorkoutAction?
}

/// The level-triggered rules from ADR 0005, for iPhone-writer workouts.
///
/// Each pass compares a workout's committed state with its ledger entry and returns at most one
/// action. It never replays events, so the result depends only on the current state.
public enum AppleHealthWorkoutPolicy {
    public static func decide(
        workoutID: UUID,
        snapshot: AppleHealthWorkoutSnapshot?,
        entry existingEntry: AppleHealthLedgerEntry?,
        hasLiveSession: Bool,
        environment: AppleHealthEnvironment
    ) -> AppleHealthWorkoutDecision {
        let discardLive: AppleHealthWorkoutAction? = hasLiveSession ? .discardSession(workoutID: workoutID) : nil

        guard var entry = existingEntry ?? observedEntry(for: snapshot) else {
            // Not started on this device, for example a workout that arrived by sync.
            return AppleHealthWorkoutDecision(entry: nil, action: discardLive)
        }

        if entry.isTerminal {
            return AppleHealthWorkoutDecision(entry: entry, action: discardLive)
        }

        // A missing row (local-data reset, account deletion), a tombstone, or a discard: no Health copy.
        guard let snapshot, !snapshot.isDeleted, snapshot.status != .discarded else {
            entry.phase = .abandoned
            return AppleHealthWorkoutDecision(entry: entry, action: discardLive)
        }

        switch snapshot.status {
        case .active:
            return decideActive(snapshot, entry: entry, hasLiveSession: hasLiveSession, environment: environment)
        case .completed:
            return decideCompleted(snapshot, entry: entry, hasLiveSession: hasLiveSession, environment: environment)
        case .discarded:
            preconditionFailure("Handled above")
        }
    }

    private static func observedEntry(for snapshot: AppleHealthWorkoutSnapshot?) -> AppleHealthLedgerEntry? {
        // Active Workouts never sync (ADR 0004), so an active workout here was started on this device.
        guard let snapshot, snapshot.status == .active, !snapshot.isDeleted else { return nil }
        return AppleHealthLedgerEntry(workoutID: snapshot.workoutID)
    }

    private static func decideActive(
        _ snapshot: AppleHealthWorkoutSnapshot,
        entry: AppleHealthLedgerEntry,
        hasLiveSession: Bool,
        environment: AppleHealthEnvironment
    ) -> AppleHealthWorkoutDecision {
        var entry = entry
        let id = snapshot.workoutID
        let hasBegun = entry.writer == .iPhone

        // Setting turned off, or write permission revoked, after recording began: write nothing.
        if hasBegun, !environment.allowsWriting {
            entry.writer = .none
            entry.phase = .abandoned
            return AppleHealthWorkoutDecision(entry: entry, action: hasLiveSession ? .discardSession(workoutID: id) : nil)
        }

        if hasLiveSession {
            let age = entry.sessionStartedAt.map { environment.now.timeIntervalSince($0) } ?? 0
            if !snapshot.isVisible || age > AppleHealthEnvironment.maximumSessionAge {
                // Hidden by sign-out, or running too long: end it. The fallback saves the workout at finish.
                entry.phase = .sessionLost
                return AppleHealthWorkoutDecision(entry: entry, action: .discardSession(workoutID: id))
            }
            return AppleHealthWorkoutDecision(entry: entry, action: nil)
        }

        if entry.phase == .recording {
            // The session ended without Baros asking: a crash, a reboot, or another app's session.
            entry.phase = .sessionLost
            return AppleHealthWorkoutDecision(entry: entry, action: nil)
        }

        let isFreshStart = environment.now.timeIntervalSince(snapshot.startedAt) <= AppleHealthEnvironment.liveStartWindow
        guard
            entry.writer == .undecided,
            entry.phase == .observed,
            environment.allowsWriting,
            snapshot.isVisible,
            isFreshStart
        else {
            return AppleHealthWorkoutDecision(entry: entry, action: nil)
        }

        let version = AppleHealthSyncVersion.next(updatedAt: snapshot.updatedAt, lastWritten: entry.lastWrittenVersion)
        entry.writer = .iPhone
        entry.phase = .recording
        entry.sessionStartedAt = environment.now
        entry.lastWrittenVersion = version
        return AppleHealthWorkoutDecision(
            entry: entry,
            action: .startSession(workoutID: id, startedAt: snapshot.startedAt, syncVersion: version)
        )
    }

    private static func decideCompleted(
        _ snapshot: AppleHealthWorkoutSnapshot,
        entry: AppleHealthLedgerEntry,
        hasLiveSession: Bool,
        environment: AppleHealthEnvironment
    ) -> AppleHealthWorkoutDecision {
        var entry = entry
        let id = snapshot.workoutID

        guard environment.allowsWriting, let endedAt = snapshot.endedAt else {
            // Finished while the setting is off or permission is missing: this workout is never written,
            // even if the setting is turned on later.
            entry.writer = .none
            entry.phase = .abandoned
            return AppleHealthWorkoutDecision(entry: entry, action: hasLiveSession ? .discardSession(workoutID: id) : nil)
        }

        if hasLiveSession, entry.phase == .recording {
            return AppleHealthWorkoutDecision(entry: entry, action: .finishSession(workoutID: id, endedAt: endedAt))
        }

        let version = AppleHealthSyncVersion.next(updatedAt: snapshot.updatedAt, lastWritten: entry.lastWrittenVersion)
        entry.writer = .iPhone
        entry.phase = .sessionLost
        return AppleHealthWorkoutDecision(
            entry: entry,
            action: hasLiveSession
                ? .discardSession(workoutID: id)
                : .saveWorkout(workoutID: id, startedAt: snapshot.startedAt, endedAt: endedAt, syncVersion: version)
        )
    }
}
