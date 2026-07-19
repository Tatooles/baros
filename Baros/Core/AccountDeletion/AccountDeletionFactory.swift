import ClerkKit
import SwiftData
import SwiftUI

struct AccountDeletionFactory {
    let makeCoordinator: @MainActor (
        _ modelContext: ModelContext,
        _ syncScheduler: SyncScheduler,
        _ clerk: Clerk
    ) -> AccountDeletionCoordinator

    static func live(syncClient: any SyncClient & Sendable) -> AccountDeletionFactory {
        AccountDeletionFactory { modelContext, syncScheduler, clerk in
            AccountDeletionCoordinator(
                syncClient: syncClient,
                accountDeleter: ClerkAccountDeleter(clerk: clerk),
                attemptStore: UserDefaultsAccountDeletionAttemptStore(),
                localDataResetService: LocalDataResetService(),
                syncScheduler: syncScheduler,
                modelContext: modelContext
            )
        }
    }
}

private struct AccountDeletionFactoryKey: EnvironmentKey {
    static let defaultValue = AccountDeletionFactory { _, _, _ in
        fatalError("AccountDeletionFactory must be injected by the app.")
    }
}

extension EnvironmentValues {
    var accountDeletionFactory: AccountDeletionFactory {
        get { self[AccountDeletionFactoryKey.self] }
        set { self[AccountDeletionFactoryKey.self] = newValue }
    }
}
