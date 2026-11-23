import Foundation
import HealthKit
import Observation
import WatchConnectivity

/// The Watch writer (ADR 0005). It owns the primary workout session that the iPhone launches, mirrors
/// it to the iPhone, and saves only on a `finish` that names the token from the iPhone's claim. Every
/// other ending discards, so a lost or late message can never produce a Health copy.
@MainActor
@Observable
final class WatchWorkoutManager: NSObject {
    static let shared = WatchWorkoutManager()

    enum Phase: Equatable {
        case idle
        case waitingForClaim
        case recording
        case ending
    }

    private struct Claim: Codable {
        let workoutID: UUID
        let token: UUID
    }

    /// Without a claim by then, the session ends and discards (the iPhone has given up on the Watch).
    private static let claimDeadline: Duration = .seconds(45)
    private static let maximumSessionAge: Duration = .seconds(6 * 60 * 60)
    /// After End, how long to wait for the iPhone's answer before discarding.
    private static let endReplyTimeout: Duration = .seconds(10)
    private static let stopTimeout: Duration = .seconds(10)
    private static let claimKey = "Baros.Watch.claim"
    private static let outcomesKey = "Baros.Watch.recentOutcomes"

    private(set) var phase: Phase = .idle
    private(set) var startDate: Date?
    private(set) var heartRate: Int?

    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var claim: Claim?
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var ageTask: Task<Void, Never>?
    @ObservationIgnored private var endReplyTask: Task<Void, Never>?
    @ObservationIgnored private var lastHeartRateSent = Date.distantPast

    override private init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        #if DEBUG
        // `--uitest-watch-recording` shows the recording screen with fixed values for screenshots,
        // since simulators can't run the paired iPhone and Watch together here.
        if ProcessInfo.processInfo.arguments.contains("--uitest-watch-recording") {
            phase = .recording
            startDate = .now.addingTimeInterval(-754)
            heartRate = 132
        }
        #endif
    }

    // MARK: Lifecycle

    /// Launched by the iPhone with `startWatchApp`. Starts the session and mirroring, then waits for a claim.
    func start(configuration: HKWorkoutConfiguration) async {
        guard session == nil else { return }
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            adopt(session, builder)
            session.prepare()
            session.startActivity(with: .now)
            phase = .waitingForClaim
            try await session.startMirroringToCompanionDevice()
        } catch {
            discardSession(acknowledging: false)
            return
        }
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: Self.claimDeadline)
            guard !Task.isCancelled, let self, claim == nil else { return }
            discardSession(acknowledging: false)
        }
        armAgeLimit()
    }

    /// After a crash or relaunch (`handleActiveWorkoutRecovery`): reattach, re-mirror, and ask the iPhone.
    func recover() async {
        guard session == nil, let session = try? await healthStore.recoverActiveWorkoutSession() else { return }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
        adopt(session, builder)
        isStopped = session.state == .stopped
        guard let claim = storedClaim() else {
            // Never claimed, so it can never be saved.
            discardSession(acknowledging: false)
            return
        }
        self.claim = claim
        startDate = builder.startDate
        phase = .recording
        try? await session.startMirroringToCompanionDevice()
        send(.statusRequest(workoutID: claim.workoutID, isEndRequest: false))
        armAgeLimit()
    }

    /// The End button. The iPhone decides finish or discard; without an answer, nothing is saved.
    func endFromWatch() {
        guard let claim, phase == .recording else {
            discardSession(acknowledging: false)
            return
        }
        send(.statusRequest(workoutID: claim.workoutID, isEndRequest: true))
        endReplyTask?.cancel()
        endReplyTask = Task { [weak self] in
            try? await Task.sleep(for: Self.endReplyTimeout)
            guard !Task.isCancelled, let self, phase == .recording else { return }
            discardSession(acknowledging: true)
        }
    }

    // MARK: Messages

    func receive(_ message: WatchWorkoutMessage) {
        switch message {
        case let .claim(workoutID, startedAt, token, syncVersion):
            Task { await accept(Claim(workoutID: workoutID, token: token), startedAt: startedAt, syncVersion: syncVersion) }
        case let .finish(workoutID, token, endedAt):
            guard let claim, claim.workoutID == workoutID, claim.token == token, session != nil else {
                replyFromMemory(workoutID)
                return
            }
            Task { await finish(at: endedAt) }
        case let .discard(workoutID):
            guard let claim, claim.workoutID == workoutID, session != nil else {
                acknowledge(workoutID, recentOutcome(workoutID) ?? .discarded)
                return
            }
            discardSession(acknowledging: true)
        case let .continueRecording(workoutID):
            guard claim?.workoutID == workoutID else { return }
            endReplyTask?.cancel()
        case .acknowledged, .statusRequest, .heartRate:
            break // Watch → iPhone only.
        }
    }

    private func accept(_ claim: Claim, startedAt: Date, syncVersion: Int64) async {
        guard phase == .waitingForClaim, self.claim == nil, let builder else { return }
        deadlineTask?.cancel()
        self.claim = claim
        storeClaim(claim)
        do {
            try await builder.beginCollection(at: startedAt)
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: claim.workoutID.uuidString.lowercased(),
                HKMetadataKeySyncVersion: NSNumber(value: syncVersion),
            ])
        } catch {
            discardSession(acknowledging: true, outcome: .failed)
            return
        }
        startDate = startedAt
        phase = .recording
    }

    private func finish(at endedAt: Date) async {
        guard let session, let builder, let claim else { return }
        phase = .ending
        endReplyTask?.cancel()
        session.stopActivity(with: endedAt)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.stopTimeout)
        while !isStopped, session.state != .stopped, session.state != .ended, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        var outcome = WatchWorkoutMessage.Outcome.failed
        if isStopped || session.state == .stopped {
            do {
                try await builder.endCollection(at: endedAt)
                outcome = try await builder.finishWorkout() == nil ? .savedWhileLocked : .saved
            } catch {
                outcome = .failed
            }
        }
        session.end()
        if outcome == .failed { builder.discardWorkout() }
        clear()
        acknowledge(claim.workoutID, outcome)
    }

    private func discardSession(acknowledging: Bool, outcome: WatchWorkoutMessage.Outcome = .discarded) {
        let workoutID = claim?.workoutID
        session?.end()
        builder?.discardWorkout()
        clear()
        if acknowledging, let workoutID { acknowledge(workoutID, outcome) }
    }

    private func adopt(_ session: HKWorkoutSession, _ builder: HKLiveWorkoutBuilder) {
        self.session = session
        self.builder = builder
        session.delegate = self
        builder.delegate = self
        isStopped = false
    }

    private func clear() {
        deadlineTask?.cancel()
        ageTask?.cancel()
        endReplyTask?.cancel()
        session = nil
        builder = nil
        claim = nil
        startDate = nil
        heartRate = nil
        phase = .idle
        UserDefaults.standard.removeObject(forKey: Self.claimKey)
    }

    private func armAgeLimit() {
        ageTask?.cancel()
        ageTask = Task { [weak self] in
            try? await Task.sleep(for: Self.maximumSessionAge)
            guard !Task.isCancelled, let self else { return }
            discardSession(acknowledging: true)
        }
    }

    // MARK: Delivery

    private func send(_ message: WatchWorkoutMessage) {
        guard let data = message.encoded() else { return }
        if let session {
            Task { try? await session.sendToRemoteWorkoutSession(data: data) }
        }
        if message.isDurable, WCSession.isSupported(), WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo([WatchWorkoutMessage.userInfoKey: data])
        }
    }

    private func acknowledge(_ workoutID: UUID, _ outcome: WatchWorkoutMessage.Outcome) {
        rememberOutcome(outcome, for: workoutID)
        send(.acknowledged(workoutID: workoutID, outcome: outcome))
    }

    /// A repeated command for a workout this Watch already finished: repeat the answer.
    private func replyFromMemory(_ workoutID: UUID) {
        acknowledge(workoutID, recentOutcome(workoutID) ?? .failed)
    }

    private func storeClaim(_ claim: Claim) {
        UserDefaults.standard.set(try? JSONEncoder().encode(claim), forKey: Self.claimKey)
    }

    private func storedClaim() -> Claim? {
        guard let data = UserDefaults.standard.data(forKey: Self.claimKey) else { return nil }
        return try? JSONDecoder().decode(Claim.self, from: data)
    }

    private func rememberOutcome(_ outcome: WatchWorkoutMessage.Outcome, for workoutID: UUID) {
        var outcomes = UserDefaults.standard.dictionary(forKey: Self.outcomesKey) as? [String: String] ?? [:]
        outcomes[workoutID.uuidString] = outcome.rawValue
        if outcomes.count > 20 { outcomes.removeValue(forKey: outcomes.keys.sorted().first!) }
        UserDefaults.standard.set(outcomes, forKey: Self.outcomesKey)
    }

    private func recentOutcome(_ workoutID: UUID) -> WatchWorkoutMessage.Outcome? {
        let outcomes = UserDefaults.standard.dictionary(forKey: Self.outcomesKey) as? [String: String]
        return outcomes?[workoutID.uuidString].flatMap(WatchWorkoutMessage.Outcome.init(rawValue:))
    }

    // MARK: Delegate hops

    private func sessionChanged(_ session: HKWorkoutSession, to state: HKWorkoutSessionState) {
        guard session === self.session else { return }
        if state == .stopped { isStopped = true }
    }

    private func sessionFailed(_ session: HKWorkoutSession) {
        // For example, another workout app took over the Watch: nothing from this session is saved.
        guard session === self.session else { return }
        discardSession(acknowledging: true, outcome: .failed)
    }

    private func collectedHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard
            builder === self.builder,
            let statistics = builder.statistics(for: HKQuantityType(.heartRate)),
            let quantity = statistics.mostRecentQuantity()
        else { return }
        let beatsPerMinute = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        heartRate = beatsPerMinute
        let now = Date.now
        guard let claim, now.timeIntervalSince(lastHeartRateSent) >= 5 else { return }
        lastHeartRateSent = now
        send(.heartRate(workoutID: claim.workoutID, beatsPerMinute: beatsPerMinute,
                        measuredAt: statistics.mostRecentQuantityDateInterval()?.end ?? now))
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.sessionChanged(workoutSession, to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.sessionFailed(workoutSession) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap(WatchWorkoutMessage.init(data:))
        Task { @MainActor in messages.forEach(self.receive) }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        Task { @MainActor in self.collectedHeartRate(from: workoutBuilder) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchWorkoutMessage.userInfoKey] as? Data,
              let message = WatchWorkoutMessage(data: data) else { return }
        Task { @MainActor in self.receive(message) }
    }
}
