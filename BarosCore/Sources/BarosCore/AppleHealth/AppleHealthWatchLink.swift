import Foundation

/// A durable command to the Watch writer (ADR 0005, "Durable commands"). It is resent on later passes
/// until the Watch acknowledges it, and the Watch saves only on a `finish` that names its token.
public enum AppleHealthWatchCommand: Codable, Equatable, Sendable {
    case finish(workoutID: UUID, token: UUID, endedAt: Date)
    case discard(workoutID: UUID)

    public var workoutID: UUID {
        switch self {
        case let .finish(workoutID, _, _), let .discard(workoutID): workoutID
        }
    }
}

/// What the Watch reports after carrying out a command.
public enum AppleHealthWatchOutcome: String, Codable, Equatable, Sendable {
    case saved
    case savedWhileLocked
    case discarded
    /// The Watch had no session for this workout (for example, another app's workout ended it).
    case failed
}

/// The iPhone side of the Baros Watch link. The app implements it with `startWatchApp`, the mirrored
/// workout session, and WatchConnectivity; tests use a fake.
@MainActor
public protocol AppleHealthWatchLinking: AnyObject {
    /// The Baros Watch app is paired and installed.
    var isWatchAvailable: Bool { get }
    /// Launches the Watch app into a workout and waits briefly for its mirrored session. `false` means a
    /// definite or timed-out failure before any claim, so the iPhone records the workout itself.
    func prepareWatchSession(workoutID: UUID) async -> Bool
    /// Sends the claim that lets the Watch save this workout. Sent only after the ledger names the Watch.
    func sendClaim(workoutID: UUID, startedAt: Date, token: UUID, syncVersion: Int64) async
    /// Best-effort delivery over every channel; the reconciler resends until acknowledged.
    func send(_ command: AppleHealthWatchCommand)
}
