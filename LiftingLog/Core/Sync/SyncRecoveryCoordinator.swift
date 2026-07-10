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
        let sessionIdentifier: String?
        let task: Task<Void, Never>
    }

    private struct RecoveryMetadata {
        let sessionIdentifier: String?
    }

    private struct AuthenticatedStateKey: Hashable {
        let ownerTokenIdentifier: String
        let sessionIdentifier: String
    }

    private let authenticationClient: any SyncAuthenticationClient
    private let syncScheduler: SyncScheduler
    private let hasActiveSession: @MainActor () -> Bool
    private let currentSessionIdentifier: @MainActor () -> String?
    private var activeRecovery: ActiveRecovery?
    private var inFlightRecoveries: [UUID: RecoveryMetadata] = [:]
    private var earlyAuthenticatedStates: [AuthenticatedStateKey: Int] = [:]
    private var pendingAuthenticatedStates: [AuthenticatedStateKey: Int] = [:]

    var willActiveRecoveryRequestSync: Bool {
        guard let activeRecovery else { return false }
        return hasActiveSession()
            && !syncScheduler.isDeletionModeEnabled
            && syncScheduler.recoveryInvalidationGeneration == activeRecovery.recoveryInvalidationGeneration
            && currentSessionIdentifier() == activeRecovery.sessionIdentifier
    }

    init(
        authenticationClient: any SyncAuthenticationClient,
        syncScheduler: SyncScheduler,
        hasActiveSession: @MainActor @escaping () -> Bool,
        currentSessionIdentifier: @MainActor @escaping () -> String? = { nil }
    ) {
        self.authenticationClient = authenticationClient
        self.syncScheduler = syncScheduler
        self.hasActiveSession = hasActiveSession
        self.currentSessionIdentifier = currentSessionIdentifier
    }

    func shouldDeferAuthenticatedState(
        ownerTokenIdentifier: String,
        sessionIdentifier: String?
    ) -> Bool {
        guard let sessionIdentifier else { return false }
        let key = AuthenticatedStateKey(
            ownerTokenIdentifier: ownerTokenIdentifier,
            sessionIdentifier: sessionIdentifier
        )

        if Self.consumeState(key, from: &pendingAuthenticatedStates) {
            return true
        }

        let hasRecoveryForSession = inFlightRecoveries.values.contains { metadata in
            metadata.sessionIdentifier == sessionIdentifier
        }
        guard hasRecoveryForSession else { return false }

        earlyAuthenticatedStates[key, default: 0] += 1
        return true
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
        let recoveryInvalidationGeneration = syncScheduler.recoveryInvalidationGeneration
        let recoverySessionIdentifier = currentSessionIdentifier()
        inFlightRecoveries[recoveryID] = RecoveryMetadata(
            sessionIdentifier: recoverySessionIdentifier
        )
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { finishRecovery(recoveryID) }

            guard !Task.isCancelled,
                  isRecoveryValid(
                      recoveryInvalidationGeneration,
                      sessionIdentifier: recoverySessionIdentifier
                  ) else {
                return
            }
            let result = await authenticationClient.loginFromCache()
            guard case .success(let token) = result,
                  let ownerTokenIdentifier = ClerkJWTIdentityResolver.ownerTokenIdentifier(from: token) else {
                return
            }
            registerAuthenticatedState(
                ownerTokenIdentifier: ownerTokenIdentifier,
                recoveryID: recoveryID
            )
            guard !Task.isCancelled,
                  isRecoveryValid(
                      recoveryInvalidationGeneration,
                      sessionIdentifier: recoverySessionIdentifier
                  ) else {
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
            sessionIdentifier: recoverySessionIdentifier,
            task: task
        )
        await task.value
        if activeRecovery?.id == recoveryID {
            activeRecovery = nil
        }
    }

    private func isRecoveryValid(
        _ recoveryInvalidationGeneration: UInt,
        sessionIdentifier: String?
    ) -> Bool {
        hasActiveSession()
            && !syncScheduler.isDeletionModeEnabled
            && syncScheduler.recoveryInvalidationGeneration == recoveryInvalidationGeneration
            && currentSessionIdentifier() == sessionIdentifier
    }

    private func registerAuthenticatedState(
        ownerTokenIdentifier: String,
        recoveryID: UUID
    ) {
        guard let sessionIdentifier = inFlightRecoveries[recoveryID]?.sessionIdentifier else {
            return
        }
        let key = AuthenticatedStateKey(
            ownerTokenIdentifier: ownerTokenIdentifier,
            sessionIdentifier: sessionIdentifier
        )

        if !Self.consumeState(key, from: &earlyAuthenticatedStates) {
            pendingAuthenticatedStates[key, default: 0] += 1
        }
    }

    private func finishRecovery(_ recoveryID: UUID) {
        let sessionIdentifier = inFlightRecoveries.removeValue(forKey: recoveryID)?.sessionIdentifier
        guard let sessionIdentifier else { return }
        let stillHasRecoveryForSession = inFlightRecoveries.values.contains { metadata in
            metadata.sessionIdentifier == sessionIdentifier
        }
        if !stillHasRecoveryForSession {
            earlyAuthenticatedStates = earlyAuthenticatedStates.filter { key, _ in
                key.sessionIdentifier != sessionIdentifier
            }
        }
    }

    private static func consumeState(
        _ key: AuthenticatedStateKey,
        from states: inout [AuthenticatedStateKey: Int]
    ) -> Bool {
        guard let count = states[key], count > 0 else { return false }
        if count == 1 {
            states[key] = nil
        } else {
            states[key] = count - 1
        }
        return true
    }
}
