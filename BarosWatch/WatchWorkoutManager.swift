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
    private static let claimDeadline: TimeInterval = 45
    private static let maximumSessionAge: TimeInterval = 6 * 60 * 60
    /// After End, how long to wait for the iPhone's answer before discarding.
    private static let endReplyTimeout: Duration = .seconds(10)
    /// How long commands for a stored claim wait for crash recovery before being answered.
    private static let recoveryWait: Duration = .seconds(15)
    private static let stopTimeout: Duration = .seconds(10)
    private static let claimKey = "Baros.Watch.claim"
    private static let outcomesKey = "Baros.Watch.recentOutcomes"

    private(set) var phase: Phase = .idle
    private(set) var startDate: Date?
    private(set) var heartRate: Int?

    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    /// Identifies this session in the readiness handshake, so a claim can't land on another session.
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var claim: Claim?
    /// The claim is bound, but `beginCollection` and the metadata aren't done yet.
    @ObservationIgnored private var isSettingUp = false
    /// A stored claim exists and recovery hasn't said whether its session survived.
    @ObservationIgnored private var isAwaitingRecovery = false
    /// Finish or discard commands that arrived before the session could act on them.
    @ObservationIgnored private var heldCommands: [WatchWorkoutMessage] = []
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var ageTask: Task<Void, Never>?
    @ObservationIgnored private var endReplyTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryWaitTask: Task<Void, Never>?
    @ObservationIgnored private var lastHeartRateSent = Date.distantPast

    override private init() {
        super.init()
        isAwaitingRecovery = storedClaim() != nil
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

    /// Launched by the iPhone with `startWatchApp`. Starts the session and mirroring, then tells the iPhone
    /// it's ready for a claim.
    func start(configuration: HKWorkoutConfiguration) async {
        guard session == nil else { return }
        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            return
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        let sessionID = UUID()
        let sessionStartedAt = Date.now
        adopt(session, builder, sessionID: sessionID)
        session.prepare()
        session.startActivity(with: sessionStartedAt)
        phase = .waitingForClaim
        // Deadlines are armed before any wait, so a slow mirror can't extend an unclaimed session.
        deadlineTask = sessionTask(for: session, after: Self.claimDeadline) { manager in
            guard manager.claim == nil else { return }
            manager.discardSession(acknowledging: false)
        }
        armAgeLimit(for: session, startedAt: .now)
        do {
            try await session.startMirroringToCompanionDevice()
        } catch {
            if self.session === session { discardSession(acknowledging: false) }
            return
        }
        guard self.session === session else { return }
        send(.readyForClaim(sessionID: sessionID, sessionStartedAt: sessionStartedAt))
    }

    /// After a crash or relaunch (`handleActiveWorkoutRecovery`): reattach, re-mirror, and ask the iPhone.
    func recover() async {
        defer { finishAwaitingRecovery() }
        guard session == nil else { return }
        guard let session = try? await healthStore.recoverActiveWorkoutSession() else {
            UserDefaults.standard.removeObject(forKey: Self.claimKey)
            return
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
        adopt(session, builder, sessionID: UUID())
        isStopped = session.state == .stopped
        guard let claim = storedClaim() else {
            // Never claimed, so it can never be saved.
            discardSession(acknowledging: false)
            return
        }
        self.claim = claim
        let startedAt = builder.startDate ?? .now
        startDate = startedAt
        phase = .recording
        armAgeLimit(for: session, startedAt: startedAt)
        try? await session.startMirroringToCompanionDevice()
        guard self.session === session else { return }
        send(.statusRequest(workoutID: claim.workoutID, token: claim.token, isEndRequest: false))
    }

    /// The End button. The iPhone decides finish or discard; without an answer, nothing is saved.
    func endFromWatch() {
        // Setting up or already saving: End has nothing to do (a confirmation may still be on screen).
        guard !isSettingUp, phase != .ending else { return }
        guard let claim, phase == .recording, let session else {
            discardSession(acknowledging: false)
            return
        }
        send(.statusRequest(workoutID: claim.workoutID, token: claim.token, isEndRequest: true))
        endReplyTask?.cancel()
        endReplyTask = Task { [weak self] in
            try? await Task.sleep(for: Self.endReplyTimeout)
            guard !Task.isCancelled, let self, self.session === session, phase == .recording else { return }
            discardSession(acknowledging: true)
        }
    }

    // MARK: Messages

    func receive(_ message: WatchWorkoutMessage) {
        switch message {
        case let .claim(workoutID, startedAt, token, syncVersion, claimSessionID):
            // Bind synchronously, so a finish in the same batch sees the claim.
            guard phase == .waitingForClaim, claim == nil, claimSessionID == sessionID, let session, let builder else { return }
            deadlineTask?.cancel()
            let claim = Claim(workoutID: workoutID, token: token)
            self.claim = claim
            storeClaim(claim)
            isSettingUp = true
            phase = .recording
            startDate = startedAt
            Task { await setUp(session, builder, startedAt: startedAt, workoutID: workoutID, syncVersion: syncVersion) }
        case let .finish(workoutID, token, _), let .discard(workoutID, token):
            handleTerminal(message, workoutID: workoutID, token: token)
        case let .declineClaim(declinedSessionID):
            // The iPhone isn't waiting for this session (for example, its launch timed out).
            guard declinedSessionID == sessionID, claim == nil else { return }
            discardSession(acknowledging: false)
        case let .continueRecording(workoutID):
            guard claim?.workoutID == workoutID else { return }
            endReplyTask?.cancel()
        case .acknowledged, .statusRequest, .heartRate, .readyForClaim:
            break // Watch → iPhone only.
        }
    }

    private func handleTerminal(_ message: WatchWorkoutMessage, workoutID: UUID, token: UUID) {
        if isSettingUp, claim?.workoutID == workoutID {
            heldCommands.append(message)
            if case .finish = message { endReplyTask?.cancel() }
            return
        }
        if isAwaitingRecovery, storedClaim()?.workoutID == workoutID {
            heldCommands.append(message)
            armRecoveryWait()
            return
        }
        guard let claim, claim.workoutID == workoutID, claim.token == token, session != nil else {
            // Not this session's claim: repeat an earlier answer, or report there's nothing to save.
            let fallback: WatchWorkoutMessage.Outcome = if case .discard = message { .discarded } else { .failed }
            send(.acknowledged(workoutID: workoutID, token: token, outcome: recentOutcome(workoutID, token) ?? fallback))
            return
        }
        guard phase != .ending else { return } // Already finishing or discarding; the outcome follows.
        switch message {
        case let .finish(_, _, endedAt):
            phase = .ending
            // Nothing else may end this session while it saves.
            deadlineTask?.cancel()
            ageTask?.cancel()
            endReplyTask?.cancel()
            Task { await finish(at: endedAt) }
        default:
            discardSession(acknowledging: true)
        }
    }

    private func setUp(
        _ session: HKWorkoutSession,
        _ builder: HKLiveWorkoutBuilder,
        startedAt: Date,
        workoutID: UUID,
        syncVersion: Int64
    ) async {
        do {
            try await builder.beginCollection(at: startedAt)
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: workoutID.uuidString.lowercased(),
                HKMetadataKeySyncVersion: NSNumber(value: syncVersion),
            ])
        } catch {
            guard self.session === session else { return }
            isSettingUp = false
            heldCommands = []
            discardSession(acknowledging: true, outcome: .failed)
            return
        }
        guard self.session === session else { return }
        isSettingUp = false
        flushHeldCommands()
    }

    private func finish(at endedAt: Date) async {
        guard let session, let builder, let claim else { return }
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
        // Only clean up the session this finish started with.
        if self.session === session { clear() }
        acknowledge(claim.workoutID, claim.token, outcome)
    }

    private func discardSession(acknowledging: Bool, outcome: WatchWorkoutMessage.Outcome = .discarded) {
        let claim = claim
        session?.end()
        builder?.discardWorkout()
        clear()
        if acknowledging, let claim { acknowledge(claim.workoutID, claim.token, outcome) }
    }

    private func adopt(_ session: HKWorkoutSession, _ builder: HKLiveWorkoutBuilder, sessionID: UUID) {
        self.session = session
        self.builder = builder
        self.sessionID = sessionID
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
        sessionID = nil
        claim = nil
        isSettingUp = false
        startDate = nil
        heartRate = nil
        phase = .idle
        UserDefaults.standard.removeObject(forKey: Self.claimKey)
    }

    private func flushHeldCommands() {
        let held = heldCommands
        heldCommands = []
        for message in held {
            if case let .finish(workoutID, token, _) = message { handleTerminal(message, workoutID: workoutID, token: token) }
            if case let .discard(workoutID, token) = message { handleTerminal(message, workoutID: workoutID, token: token) }
        }
    }

    private func finishAwaitingRecovery() {
        guard isAwaitingRecovery else { return }
        isAwaitingRecovery = false
        recoveryWaitTask?.cancel()
        flushHeldCommands()
    }

    private func armRecoveryWait() {
        guard recoveryWaitTask == nil else { return }
        recoveryWaitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.recoveryWait)
            guard !Task.isCancelled, let self else { return }
            // No session came back: answer the held commands (nothing to save).
            recoveryWaitTask = nil
            if session == nil { UserDefaults.standard.removeObject(forKey: Self.claimKey) }
            finishAwaitingRecovery()
        }
    }

    /// A task that runs once after `delay`, and only if `session` is still the current one.
    private func sessionTask(
        for session: HKWorkoutSession,
        after delay: TimeInterval,
        _ action: @escaping @MainActor (WatchWorkoutManager) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled, let self, self.session === session else { return }
            action(self)
        }
    }

    /// The age limit counts from the session's original start, including across a recovery.
    private func armAgeLimit(for session: HKWorkoutSession, startedAt: Date) {
        ageTask?.cancel()
        let remaining = Self.maximumSessionAge - Date.now.timeIntervalSince(startedAt)
        ageTask = sessionTask(for: session, after: remaining) { manager in
            manager.discardSession(acknowledging: true)
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

    /// Reports what this Watch actually did with its own claim, and remembers it for repeated commands.
    private func acknowledge(_ workoutID: UUID, _ token: UUID, _ outcome: WatchWorkoutMessage.Outcome) {
        rememberOutcome(outcome, for: workoutID, token: token)
        send(.acknowledged(workoutID: workoutID, token: token, outcome: outcome))
    }

    private func storeClaim(_ claim: Claim) {
        UserDefaults.standard.set(try? JSONEncoder().encode(claim), forKey: Self.claimKey)
    }

    private func storedClaim() -> Claim? {
        guard let data = UserDefaults.standard.data(forKey: Self.claimKey) else { return nil }
        return try? JSONDecoder().decode(Claim.self, from: data)
    }

    private static func outcomeKey(_ workoutID: UUID, _ token: UUID) -> String {
        "\(workoutID.uuidString)|\(token.uuidString)"
    }

    private func rememberOutcome(_ outcome: WatchWorkoutMessage.Outcome, for workoutID: UUID, token: UUID) {
        var outcomes = UserDefaults.standard.dictionary(forKey: Self.outcomesKey) as? [String: String] ?? [:]
        outcomes[Self.outcomeKey(workoutID, token)] = outcome.rawValue
        if outcomes.count > 20, let oldest = outcomes.keys.sorted().first { outcomes.removeValue(forKey: oldest) }
        UserDefaults.standard.set(outcomes, forKey: Self.outcomesKey)
    }

    private func recentOutcome(_ workoutID: UUID, _ token: UUID) -> WatchWorkoutMessage.Outcome? {
        let outcomes = UserDefaults.standard.dictionary(forKey: Self.outcomesKey) as? [String: String]
        return outcomes?[Self.outcomeKey(workoutID, token)].flatMap(WatchWorkoutMessage.Outcome.init(rawValue:))
    }

    // MARK: Delegate hops

    private func sessionChanged(_ session: HKWorkoutSession, to state: HKWorkoutSessionState) {
        guard session === self.session else { return }
        if state == .stopped { isStopped = true }
    }

    private func sessionFailed(_ session: HKWorkoutSession) {
        // For example, another workout app took over the Watch: nothing from this session is saved.
        guard session === self.session, phase != .ending else { return }
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
