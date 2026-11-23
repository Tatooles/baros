import BarosCore
import Foundation
import HealthKit
import WatchConnectivity

/// The iPhone side of the Baros Watch link (ADR 0005, "Watch writer"): launches the Watch app into a
/// workout, holds its mirrored session, and carries messages over the mirrored session and
/// WatchConnectivity. It never touches the mirrored session's builder.
@MainActor
final class WatchWorkoutLink: NSObject, AppleHealthWatchLinking {
    /// How long to wait for the Watch's mirrored session after the launch request. A Watch left at home
    /// fails the launch quickly; a slow Watch past this falls back to the iPhone (before any claim).
    private static let mirrorTimeout: Duration = .seconds(20)

    private let healthStore: HKHealthStore
    private var mirroredSession: HKWorkoutSession?
    /// While a launch waits, the first session that reports `readyForClaim`; the claim goes to exactly it.
    private var isAwaitingReadiness = false
    private var launchRequestedAt = Date.distantFuture
    /// Allows for clock differences between iPhone and Watch.
    private static let clockTolerance: TimeInterval = 5
    private var readySession: (sessionID: UUID, session: HKWorkoutSession)?
    /// Called on the main actor with each message from the Watch.
    var onMessage: ((WatchWorkoutMessage) -> Void)?

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        // Must be set at launch so a mirrored session started while the app wasn't running is delivered.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.adopt(session) }
        }
    }

    var isWatchAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    /// Ready only when a freshly launched Watch session reports `readyForClaim`; an older session that
    /// reconnects meanwhile doesn't count.
    func prepareWatchSession(workoutID: UUID) async -> Bool {
        readySession = nil
        isAwaitingReadiness = true
        launchRequestedAt = .now
        defer { isAwaitingReadiness = false }
        do {
            try await healthStore.startWatchApp(toHandle: HealthKitWorkoutRecorder.workoutConfiguration)
        } catch {
            return false
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.mirrorTimeout)
        while readySession == nil, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return readySession != nil
    }

    func sendClaim(workoutID: UUID, startedAt: Date, token: UUID, syncVersion: Int64) async {
        guard let (sessionID, session) = readySession else { return }
        readySession = nil
        let claim = WatchWorkoutMessage.claim(
            workoutID: workoutID, startedAt: startedAt, token: token, syncVersion: syncVersion, sessionID: sessionID
        )
        guard let data = claim.encoded() else { return }
        try? await session.sendToRemoteWorkoutSession(data: data)
    }

    func send(_ command: AppleHealthWatchCommand) {
        let message: WatchWorkoutMessage = switch command {
        case let .finish(workoutID, token, endedAt): .finish(workoutID: workoutID, token: token, endedAt: endedAt)
        case let .discard(workoutID, token): .discard(workoutID: workoutID, token: token)
        }
        send(message)
    }

    /// Replies and commands: over the mirrored session when connected, and durable ones also queued with
    /// WatchConnectivity unless an identical transfer is already waiting.
    func send(_ message: WatchWorkoutMessage) {
        Task { await sendOverMirror(message) }
        guard message.isDurable, let data = message.encoded(), isWatchAvailable else { return }
        let session = WCSession.default
        let isQueued = session.outstandingUserInfoTransfers.contains {
            ($0.userInfo[WatchWorkoutMessage.userInfoKey] as? Data) == data
        }
        if !isQueued {
            session.transferUserInfo([WatchWorkoutMessage.userInfoKey: data])
        }
    }

    private func sendOverMirror(_ message: WatchWorkoutMessage) async {
        guard let mirroredSession, let data = message.encoded() else { return }
        try? await mirroredSession.sendToRemoteWorkoutSession(data: data)
    }

    private func adopt(_ session: HKWorkoutSession) {
        mirroredSession = session
        session.delegate = self
    }

    private func receive(_ data: Data, from session: HKWorkoutSession?) {
        guard let message = WatchWorkoutMessage(data: data) else { return }
        if case let .readyForClaim(sessionID, sessionStartedAt) = message {
            // Only a session started by this launch counts. Anything else (for example, an earlier launch
            // that timed out) is declined, and that Watch session discards.
            let isThisLaunch = sessionStartedAt >= launchRequestedAt.addingTimeInterval(-Self.clockTolerance)
            if isAwaitingReadiness, readySession == nil, isThisLaunch, let session {
                readySession = (sessionID, session)
            } else if let session, let data = WatchWorkoutMessage.declineClaim(sessionID: sessionID).encoded() {
                Task { try? await session.sendToRemoteWorkoutSession(data: data) }
            }
            return
        }
        onMessage?(message)
    }

    private func dropMirroredSession(_ session: HKWorkoutSession) {
        if mirroredSession === session { mirroredSession = nil }
        if readySession?.session === session { readySession = nil }
    }
}

extension WatchWorkoutLink: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        Task { @MainActor in self.dropMirroredSession(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in data.forEach { self.receive($0, from: workoutSession) } }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        // The mirrored session is no longer valid; durable commands still go through WatchConnectivity.
        Task { @MainActor in self.dropMirroredSession(workoutSession) }
    }
}

extension WatchWorkoutLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchWorkoutMessage.userInfoKey] as? Data else { return }
        Task { @MainActor in self.receive(data, from: nil) }
    }
}
