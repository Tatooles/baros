import SwiftUI

struct SyncRecoveryAction {
    let request: @MainActor (SyncRecoveryCoordinator.Trigger) -> Void

    @MainActor
    func callAsFunction(_ trigger: SyncRecoveryCoordinator.Trigger) {
        request(trigger)
    }
}

private struct SyncRecoveryActionKey: EnvironmentKey {
    static let defaultValue = SyncRecoveryAction { _ in }
}

extension EnvironmentValues {
    var syncRecoveryAction: SyncRecoveryAction {
        get { self[SyncRecoveryActionKey.self] }
        set { self[SyncRecoveryActionKey.self] = newValue }
    }
}
