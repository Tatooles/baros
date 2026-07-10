import Foundation
@preconcurrency import ConvexMobile

@MainActor
protocol SyncAuthenticationClient: AnyObject {
    func loginFromCache() async -> Result<String, Error>
}

@MainActor
final class ConvexSyncAuthenticationClient: SyncAuthenticationClient {
    private let client: ConvexClientWithAuth<String>

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    func loginFromCache() async -> Result<String, Error> {
        await client.loginFromCache()
    }
}

@MainActor
final class SyncRecoveryCoordinator {
    enum Trigger {
        case appForeground
        case manualRetry
    }

    private struct ActiveRecovery {
        let id: UUID
        let recoveryInvalidationGeneration: UInt
        let task: Task<Void, Never>
    }

    private let authenticationClient: any SyncAuthenticationClient
    private let syncScheduler: SyncScheduler
    private let hasActiveSession: @MainActor () -> Bool
    private var activeRecovery: ActiveRecovery?

    var willActiveRecoveryRequestSync: Bool {
        guard let activeRecovery else { return false }
        return hasActiveSession()
            && !syncScheduler.isDeletionModeEnabled
            && syncScheduler.recoveryInvalidationGeneration == activeRecovery.recoveryInvalidationGeneration
    }

    init(
        authenticationClient: any SyncAuthenticationClient,
        syncScheduler: SyncScheduler,
        hasActiveSession: @MainActor @escaping () -> Bool
    ) {
        self.authenticationClient = authenticationClient
        self.syncScheduler = syncScheduler
        self.hasActiveSession = hasActiveSession
    }

    func recoverAuthenticationAndRequestSync(for trigger: Trigger) async {
        if let activeRecovery {
            if willActiveRecoveryRequestSync {
                await activeRecovery.task.value
                return
            }

            activeRecovery.task.cancel()
            self.activeRecovery = nil
        }

        guard hasActiveSession(), !syncScheduler.isDeletionModeEnabled else {
            return
        }

        let recoveryID = UUID()
        let authenticationClient = self.authenticationClient
        let syncScheduler = self.syncScheduler
        let hasActiveSession = self.hasActiveSession
        let recoveryInvalidationGeneration = syncScheduler.recoveryInvalidationGeneration
        let task = Task { @MainActor in
            guard hasActiveSession(),
                  !syncScheduler.isDeletionModeEnabled,
                  syncScheduler.recoveryInvalidationGeneration == recoveryInvalidationGeneration else {
                return
            }
            let result = await authenticationClient.loginFromCache()
            guard hasActiveSession(),
                  !syncScheduler.isDeletionModeEnabled,
                  syncScheduler.recoveryInvalidationGeneration == recoveryInvalidationGeneration else {
                return
            }
            guard case .success(let token) = result,
                  let ownerTokenIdentifier = ClerkJWTIdentityResolver.ownerTokenIdentifier(from: token) else {
                return
            }

            syncScheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
            syncScheduler.seedDefaultsForCurrentOwner()
            switch trigger {
            case .appForeground:
                syncScheduler.requestSyncOnAppForeground()
            case .manualRetry:
                syncScheduler.retrySync()
            }
        }

        activeRecovery = ActiveRecovery(
            id: recoveryID,
            recoveryInvalidationGeneration: recoveryInvalidationGeneration,
            task: task
        )
        await task.value
        if activeRecovery?.id == recoveryID {
            activeRecovery = nil
        }
    }
}
