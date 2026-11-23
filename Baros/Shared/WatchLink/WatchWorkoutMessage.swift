import Foundation

/// Messages between the iPhone and the Baros Watch app about the Watch-owned Health workout
/// (ADR 0005, "Watch writer"). Compiled into both apps; Foundation only.
///
/// They travel over the mirrored workout session when it's connected, and the durable ones (claim
/// excepted) also over WatchConnectivity `transferUserInfo`, so a command sent while the Watch is
/// out of range arrives later. Every message is idempotent by workout ID and token.
enum WatchWorkoutMessage: Codable, Equatable, Sendable {
    /// Watch → iPhone: a freshly launched session is mirrored and waiting for a claim. The start time
    /// lets the iPhone tell this launch from an earlier, abandoned one.
    case readyForClaim(sessionID: UUID, sessionStartedAt: Date)
    /// iPhone → Watch: the iPhone isn't waiting for this session; end it and save nothing.
    case declineClaim(sessionID: UUID)
    /// iPhone → Watch: the Watch may save this workout, and only on a `finish` naming `token`. It names
    /// the session that reported ready, so it can't land on another session.
    case claim(workoutID: UUID, startedAt: Date, token: UUID, syncVersion: Int64, sessionID: UUID)
    /// iPhone → Watch: save the workout ending at `endedAt`.
    case finish(workoutID: UUID, token: UUID, endedAt: Date)
    /// iPhone → Watch: end the session and save nothing.
    case discard(workoutID: UUID, token: UUID)
    /// iPhone → Watch: the Baros workout is still active; keep recording.
    case continueRecording(workoutID: UUID)
    /// Watch → iPhone: the result of a finish or discard.
    case acknowledged(workoutID: UUID, token: UUID, outcome: Outcome)
    /// Watch → iPhone: what should happen to this session (after a relaunch, or from the End button).
    case statusRequest(workoutID: UUID, token: UUID, isEndRequest: Bool)
    /// Watch → iPhone: the latest heart rate for the workout header. Never stored.
    case heartRate(workoutID: UUID, beatsPerMinute: Int, measuredAt: Date)

    enum Outcome: String, Codable, Sendable {
        case saved
        case savedWhileLocked
        case discarded
        case failed
    }

    static let userInfoKey = "baros.watchWorkoutMessage"

    /// Sorted keys, so identical messages encode identically (queued transfers are deduplicated by bytes).
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(self)
    }

    init?(data: Data) {
        guard let message = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = message
    }

    /// Commands the iPhone also queues with `transferUserInfo`, so they survive the Watch being away.
    var isDurable: Bool {
        switch self {
        case .finish, .discard, .acknowledged: true
        case .readyForClaim, .declineClaim, .claim, .continueRecording, .statusRequest, .heartRate: false
        }
    }
}
