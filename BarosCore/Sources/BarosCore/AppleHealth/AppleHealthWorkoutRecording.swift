import Foundation

/// How a HealthKit call failed. Only authorization and invalid-input errors are terminal (ADR 0005).
/// Anything else, such as a locked phone's inaccessible database, is retried on a later pass.
public enum AppleHealthRecordingFailure: Error, Equatable, Sendable {
    case terminal
    case transient
}

/// What a successful save returned. A locked phone can save a workout without returning it.
public enum AppleHealthSaveConfirmation: Equatable, Sendable {
    case visible
    case savedWhileLocked
}

/// This device's Health copy of a workout, as found by sync identifier.
public struct AppleHealthSavedCopy: Equatable, Sendable {
    public let syncVersion: Int64?
    public let startedAt: Date
    public let endedAt: Date

    public init(syncVersion: Int64?, startedAt: Date, endedAt: Date) {
        self.syncVersion = syncVersion
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

/// The HealthKit side of the recorder. The app implements it with `HKWorkoutSession`; tests use a fake.
///
/// Implementations must follow ADR 0005's session lifetime: after one bounded finish or discard
/// attempt, the session is ended and no longer reported by `liveSessionWorkoutIDs()`, even when the
/// save failed.
@MainActor
public protocol AppleHealthWorkoutRecording: AnyObject {
    func authorization() -> AppleHealthAuthorization
    func liveSessionWorkoutIDs() -> Set<UUID>
    func startSession(workoutID: UUID, startedAt: Date, syncVersion: Int64) async throws(AppleHealthRecordingFailure)
    func finishSession(
        workoutID: UUID,
        endedAt: Date
    ) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation
    func discardSession(workoutID: UUID) async
    /// This device's Health copy, matched by sync identifier, if one exists. Called before any retry or
    /// fallback save, so a save that succeeded without being recorded isn't repeated.
    func savedWorkout(workoutID: UUID) async throws(AppleHealthRecordingFailure) -> AppleHealthSavedCopy?
    func saveWorkout(
        workoutID: UUID,
        startedAt: Date,
        endedAt: Date,
        syncVersion: Int64
    ) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation
}

/// Committed Baros state for the recorder. Implementations read only saved records.
@MainActor
public protocol AppleHealthWorkoutSnapshotSource: AnyObject {
    /// Every active workout on this device, plus any of `workoutIDs` that still exist. A workout
    /// that's absent from the result is a missing row. A fetch that throws means "unknown", never "missing".
    func snapshots(includingWorkoutIDs workoutIDs: Set<UUID>) throws -> [AppleHealthWorkoutSnapshot]
}
