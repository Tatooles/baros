import Foundation

/// A committed, immutable view of one Baros workout, as the Apple Health recorder sees it.
///
/// The recorder never reads or writes `WorkoutSession` directly (ADR 0005). It only compares
/// these snapshots with its device-local ledger.
public struct AppleHealthWorkoutSnapshot: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case active
        case completed
        case discarded
    }

    public let workoutID: UUID
    public let status: Status
    public let startedAt: Date
    public let endedAt: Date?
    public let updatedAt: Date
    /// The workout has a `deletedAt` tombstone. Only a tombstone, never a missing row, means deleted.
    public let isDeleted: Bool
    /// The Current Owner can see this workout. An Active Workout hidden by sign-out (ADR 0004) is not visible.
    public let isVisible: Bool

    public init(
        workoutID: UUID,
        status: Status,
        startedAt: Date,
        endedAt: Date?,
        updatedAt: Date,
        isDeleted: Bool,
        isVisible: Bool
    ) {
        self.workoutID = workoutID
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.isVisible = isVisible
    }
}

/// Whether Baros may write workouts to Apple Health. It reflects write authorization for workouts,
/// which HealthKit reports. Read authorization is never observable.
public enum AppleHealthAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public struct AppleHealthEnvironment: Equatable, Sendable {
    /// A live session starts only for a workout seen within this window of its start. Later, for
    /// example after the setting is turned on mid-workout, the fallback saves the workout at finish.
    public static let liveStartWindow: TimeInterval = 5 * 60
    /// A live session older than this is discarded; the fallback can still save the workout at finish.
    public static let maximumSessionAge: TimeInterval = 6 * 60 * 60

    public let isSettingEnabled: Bool
    public let authorization: AppleHealthAuthorization
    public let now: Date
    /// The Baros Watch app is paired and installed, so a new workout tries the Watch first.
    public let isWatchAvailable: Bool

    public init(
        isSettingEnabled: Bool,
        authorization: AppleHealthAuthorization,
        now: Date,
        isWatchAvailable: Bool = false
    ) {
        self.isSettingEnabled = isSettingEnabled
        self.authorization = authorization
        self.now = now
        self.isWatchAvailable = isWatchAvailable
    }

    var allowsWriting: Bool {
        isSettingEnabled && authorization == .authorized
    }
}

public enum AppleHealthSyncVersion {
    /// The `HKMetadataKeySyncVersion` for a save. HealthKit replaces a saved object only when the
    /// version is higher, so the result never goes backwards, even when `updatedAt` came from
    /// another device's clock.
    public static func next(updatedAt: Date, lastWritten: Int64?) -> Int64 {
        let milliseconds = Int64((updatedAt.timeIntervalSince1970 * 1000).rounded(.down))
        guard let lastWritten else { return milliseconds }
        return max(milliseconds, lastWritten + 1)
    }
}
