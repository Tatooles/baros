import BarosCore
import Foundation
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

    @ObservationIgnored private let recorder: HealthKitWorkoutRecorder
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let reconciler: AppleHealthWorkoutReconciler

    init(
        container: ModelContainer,
        currentOwner: @escaping @MainActor () -> SwiftDataAppleHealthSnapshotSource.CurrentOwnerVisibility,
        recorder: HealthKitWorkoutRecorder = HealthKitWorkoutRecorder(),
        defaults: UserDefaults = .standard
    ) {
        self.recorder = recorder
        self.defaults = defaults
        isEnabled = AppleHealthPreference.isEnabled(defaults: defaults)
        authorization = recorder.authorization()
        reconciler = AppleHealthWorkoutReconciler(
            recorder: recorder,
            ledger: AppleHealthLedgerStore(defaults: defaults),
            snapshotSource: SwiftDataAppleHealthSnapshotSource(container: container, currentOwner: currentOwner),
            isSettingEnabled: { [defaults] in AppleHealthPreference.isEnabled(defaults: defaults) }
        )
    }

    var settingState: SettingState {
        switch authorization {
        case .unavailable: .unavailable
        case .denied where isEnabled: .accessDenied
        case .notDetermined where isEnabled: .accessDenied
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
        isEnabled = true
        AppleHealthPreference.setEnabled(true, defaults: defaults)
        requestReconciliation()
    }

    func refreshAuthorization() {
        authorization = recorder.authorization()
    }

    func requestReconciliation() {
        refreshAuthorization()
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
