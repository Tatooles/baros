import BarosCore
import Foundation
import HealthKit

/// The HealthKit adapter for `AppleHealthWorkoutRecording` (ADR 0005): an iPhone-owned
/// `HKWorkoutSession` with its live builder, plus an offline builder for the fallback save.
///
/// Every session is ended after one bounded finish or discard attempt, so a failed save never keeps
/// a session running. The iPhone never calls builder APIs on a mirrored session; this type only
/// creates primary sessions.
@MainActor
final class HealthKitWorkoutRecorder: NSObject, AppleHealthWorkoutRecording {
    /// How long a finish waits for the session to reach `.stopped` before saving anyway.
    private static let stopTimeout: Duration = .seconds(10)

    private final class LiveSession {
        let session: HKWorkoutSession
        let builder: HKLiveWorkoutBuilder
        var isStopped = false

        init(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
            self.session = session
            self.builder = builder
        }
    }

    private let healthStore: HKHealthStore
    private var liveSessions: [UUID: LiveSession] = [:]

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    static var workoutConfiguration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    func authorization() -> AppleHealthAuthorization {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch healthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func liveSessionWorkoutIDs() -> Set<UUID> {
        Set(liveSessions.keys)
    }

    func startSession(
        workoutID: UUID,
        startedAt: Date,
        syncVersion: Int64
    ) async throws(AppleHealthRecordingFailure) {
        guard liveSessions[workoutID] == nil else { return }
        let configuration = Self.workoutConfiguration
        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            throw Self.failure(for: error)
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        let live = LiveSession(session: session, builder: builder)
        liveSessions[workoutID] = live

        session.prepare()
        session.startActivity(with: startedAt)
        do {
            try await builder.beginCollection(at: startedAt)
            try await builder.addMetadata(Self.metadata(workoutID: workoutID, syncVersion: syncVersion))
        } catch {
            end(live, workoutID: workoutID, discarding: true)
            throw Self.failure(for: error)
        }
    }

    func finishSession(
        workoutID: UUID,
        endedAt: Date
    ) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation {
        guard let live = liveSessions[workoutID] else { throw .transient }
        defer { end(live, workoutID: workoutID, discarding: false) }

        live.session.stopActivity(with: endedAt)
        // Touch the builder only once the session has stopped. If it doesn't stop in time, end the
        // session; the next pass looks the workout up by sync identifier before any fallback save.
        guard await waitUntilStopped(live) else { throw .transient }
        do {
            try await live.builder.endCollection(at: endedAt)
            // A locked phone can complete with neither a workout nor an error; that is still a save.
            return try await live.builder.finishWorkout() == nil ? .savedWhileLocked : .visible
        } catch {
            throw Self.failure(for: error)
        }
    }

    func discardSession(workoutID: UUID) async {
        guard let live = liveSessions[workoutID] else { return }
        end(live, workoutID: workoutID, discarding: true)
    }

    func savedWorkout(workoutID: UUID) async throws(AppleHealthRecordingFailure) -> AppleHealthSavedCopy? {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: [Self.syncIdentifier(for: workoutID)]
            ),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: 1
        )
        let workout: HKWorkout?
        do {
            workout = try await descriptor.result(for: healthStore).first
        } catch {
            throw Self.failure(for: error)
        }
        return workout.map {
            AppleHealthSavedCopy(
                syncVersion: ($0.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.int64Value,
                startedAt: $0.startDate,
                endedAt: $0.endDate
            )
        }
    }

    func saveWorkout(
        workoutID: UUID,
        startedAt: Date,
        endedAt: Date,
        syncVersion: Int64
    ) async throws(AppleHealthRecordingFailure) -> AppleHealthSaveConfirmation {
        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: Self.workoutConfiguration,
            device: .local()
        )
        do {
            try await builder.beginCollection(at: startedAt)
            try await builder.addMetadata(Self.metadata(workoutID: workoutID, syncVersion: syncVersion))
            try await builder.endCollection(at: endedAt)
            return try await builder.finishWorkout() == nil ? .savedWhileLocked : .visible
        } catch {
            builder.discardWorkout()
            throw Self.failure(for: error)
        }
    }

    // MARK: - Helpers

    static func syncIdentifier(for workoutID: UUID) -> String {
        workoutID.uuidString.lowercased()
    }

    private static func metadata(workoutID: UUID, syncVersion: Int64) -> [String: Any] {
        [
            HKMetadataKeySyncIdentifier: syncIdentifier(for: workoutID),
            HKMetadataKeySyncVersion: NSNumber(value: syncVersion),
        ]
    }

    static func failure(for error: any Error) -> AppleHealthRecordingFailure {
        guard let code = (error as? HKError)?.code else { return .transient }
        switch code {
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined, .errorInvalidArgument,
             .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return .terminal
        default:
            return .transient
        }
    }

    /// Returns whether the session reached `.stopped` within the timeout.
    private func waitUntilStopped(_ live: LiveSession) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.stopTimeout)
        // `.ended` without `.stopped` means another app or the system ended it: stop waiting.
        while !live.isStopped, live.session.state != .stopped, live.session.state != .ended, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return live.isStopped || live.session.state == .stopped
    }

    private func end(_ live: LiveSession, workoutID: UUID, discarding: Bool) {
        live.session.end()
        if discarding {
            live.builder.discardWorkout()
        }
        if liveSessions[workoutID] === live {
            liveSessions[workoutID] = nil
        }
    }

    private func handle(state: HKWorkoutSessionState, for session: HKWorkoutSession) {
        guard let live = liveSessions.values.first(where: { $0.session === session }) else { return }
        if state == .stopped {
            live.isStopped = true
        }
    }

    private func handleFailure(of session: HKWorkoutSession) {
        // For example another app's session took over. Drop it so the reconciler sees the session as
        // lost; the fallback saves the workout at finish.
        guard let (workoutID, live) = liveSessions.first(where: { $0.value.session === session }) else { return }
        end(live, workoutID: workoutID, discarding: true)
    }
}

extension HealthKitWorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.handle(state: toState, for: workoutSession)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in
            self.handleFailure(of: workoutSession)
        }
    }
}
