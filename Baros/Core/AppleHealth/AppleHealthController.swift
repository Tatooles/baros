import BarosCore
import Foundation
import HealthKit
import Observation
import SwiftData

/// Owns the **Save Workouts to Apple Health** setting and the recorder that mirrors Active Workouts
/// into Apple Health (ADR 0005). Nothing in Baros waits on it.
@MainActor
@Observable
final class AppleHealthController {
    enum SettingState: Equatable {
        /// Health isn't available on this device; the setting is hidden.
        case unavailable
        case off
        case on
        /// The setting is on in Baros, but Health access to save workouts is off.
        case accessDenied
    }

    private(set) var isEnabled: Bool
    private(set) var authorization: AppleHealthAuthorization
    private(set) var isRequestingAccess = false
    /// Latest heart rate per Active Workout, for the workout header. Never stored or uploaded.
    private(set) var heartRates: [UUID: LiveHeartRate] = [:]

    @ObservationIgnored private let recorder: HealthKitWorkoutRecorder
    @ObservationIgnored private let watchLink: WatchWorkoutLink
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reconciler: AppleHealthWorkoutReconciler
    /// Passes wait until a session HealthKit kept alive across a relaunch is reattached, so it isn't
    /// mistaken for a lost one.
    @ObservationIgnored private var isRecoveringSession = true
    @ObservationIgnored private var isReconciliationPending = false

    init(
        container: ModelContainer,
        currentOwner: @escaping @MainActor () -> SwiftDataAppleHealthSnapshotSource.CurrentOwnerVisibility,
        healthStore: HKHealthStore = HKHealthStore(),
        defaults: UserDefaults = .standard
    ) {
        let recorder = HealthKitWorkoutRecorder(healthStore: healthStore)
        let watchLink = WatchWorkoutLink(healthStore: healthStore)
        self.recorder = recorder
        self.watchLink = watchLink
        self.defaults = defaults
        isEnabled = AppleHealthPreference.isEnabled(defaults: defaults)
        authorization = recorder.authorization()
        reconciler = AppleHealthWorkoutReconciler(
            recorder: recorder,
            ledger: AppleHealthLedgerStore(defaults: defaults),
            snapshotSource: SwiftDataAppleHealthSnapshotSource(container: container, currentOwner: currentOwner),
            watchLink: watchLink,
            isSettingEnabled: { [defaults] in AppleHealthPreference.isEnabled(defaults: defaults) }
        )
        recorder.onHeartRate = { [weak self] workoutID, reading in
            self?.heartRates[workoutID] = reading
        }
        recorder.onSessionEnded = { [weak self] workoutID in
            self?.heartRates[workoutID] = nil
        }
        watchLink.onMessage = { [weak self] message in
            self?.handle(message)
        }
        Task { [weak self] in
            await recorder.recoverActiveSession()
            guard let self else { return }
            isRecoveringSession = false
            if isReconciliationPending { requestReconciliation() }
        }
    }

    /// The heart rate to show for this workout now, or `nil` to show nothing.
    func displayedHeartRate(for workoutID: UUID, at now: Date) -> Int? {
        #if DEBUG
        if let fixture = Self.uiTestHeartRate { return fixture }
        #endif
        return heartRates[workoutID]?.displayedBeatsPerMinute(at: now)
    }

    #if DEBUG
    /// `--uitest-heart-rate <bpm>` shows a fixed reading, since simulators have no heart-rate sensor.
    private static let uiTestHeartRate: Int? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--uitest-heart-rate"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Int(arguments[index + 1])
    }()
    #endif

    var settingState: SettingState {
        switch authorization {
        case .unavailable: .unavailable
        case .denied where isEnabled: .accessDenied
        default: isEnabled ? .on : .off
        }
    }

    /// Turning the setting on asks for Health access in context, once (ADR 0005, "Permissions").
    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            isEnabled = false
            AppleHealthPreference.setEnabled(false, defaults: defaults)
            requestReconciliation()
            return
        }
        isRequestingAccess = true
        authorization = await recorder.requestAuthorization()
        isRequestingAccess = false
        // The sheet failed or was dismissed without an answer: leave the setting off so it can be retried.
        guard authorization != .notDetermined, authorization != .unavailable else { return }
        isEnabled = true
        AppleHealthPreference.setEnabled(true, defaults: defaults)
        requestReconciliation()
    }

    /// Messages from the Baros Watch app (ADR 0005, "Watch writer").
    private func handle(_ message: WatchWorkoutMessage) {
        switch message {
        case let .acknowledged(workoutID, token, outcome):
            heartRates[workoutID] = nil
            let mapped: AppleHealthWatchOutcome = switch outcome {
            case .saved: .saved
            case .savedWhileLocked: .savedWhileLocked
            case .discarded: .discarded
            case .failed: .failed
            }
            reconciler.handleWatchAcknowledgement(workoutID: workoutID, token: token, outcome: mapped)
        case let .statusRequest(workoutID, token, isEndRequest):
            if let command = reconciler.watchCommand(forStatusOf: workoutID, token: token, isEndRequest: isEndRequest) {
                watchLink.send(command)
            } else {
                watchLink.send(.continueRecording(workoutID: workoutID))
            }
        case let .heartRate(workoutID, beatsPerMinute, measuredAt):
            heartRates[workoutID] = LiveHeartRate(beatsPerMinute: beatsPerMinute, measuredAt: measuredAt)
        case .readyForClaim, .declineClaim, .claim, .finish, .discard, .continueRecording:
            break // iPhone → Watch only.
        }
    }

    func refreshAuthorization() {
        authorization = recorder.authorization()
    }

    func requestReconciliation() {
        refreshAuthorization()
        guard !isRecoveringSession else {
            isReconciliationPending = true
            return
        }
        isReconciliationPending = false
        reconciler.requestReconciliation()
    }
}

extension AppleHealthController: LocalDataResetObserving {
    func localDataResetWillBegin() {
        reconciler.localDataResetWillBegin()
    }

    func localDataResetDidEnd() {
        reconciler.localDataResetDidEnd()
    }
}
