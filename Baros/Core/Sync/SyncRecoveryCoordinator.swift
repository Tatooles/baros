import Foundation
@preconcurrency import ConvexMobile

@MainActor
protocol SyncAuthenticationClient: AnyObject {
    func loginFromCache() async -> Result<String, Error>
    func logout() async
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

    func logout() async {
        await client.logout()
    }
}

private struct AuthenticatedStateCorrelation {
    struct Key: Hashable {
        let ownerTokenIdentifier: String
        let sessionIdentifier: String
    }

    private struct PendingState {
        var count: Int
        var expiresAt: Date
    }

    private let pendingLifetime: TimeInterval
    private var earlyStates: [Key: Int] = [:]
    private var pendingStates: [Key: PendingState] = [:]

    init(pendingLifetime: TimeInterval) {
        self.pendingLifetime = pendingLifetime
    }

    mutating func shouldDefer(
        key: Key,
        hasRecoveryForSession: Bool,
        now: Date
    ) -> Bool {
        discardExpiredPendingStates(now: now)
        if Self.consume(key, from: &pendingStates) {
            return true
        }
        guard hasRecoveryForSession else { return false }

        earlyStates[key, default: 0] += 1
        return true
    }

    mutating func registerRecoveryAuthentication(key: Key, now: Date) {
        discardExpiredPendingStates(now: now)
        guard !Self.consume(key, from: &earlyStates) else { return }

        let expiresAt = now.addingTimeInterval(pendingLifetime)
        if var pendingState = pendingStates[key] {
            pendingState.count += 1
            pendingState.expiresAt = expiresAt
            pendingStates[key] = pendingState
        } else {
            pendingStates[key] = PendingState(count: 1, expiresAt: expiresAt)
        }
    }

    mutating func finishRecovery(
        sessionIdentifier: String,
        stillHasRecoveryForSession: Bool,
        now: Date
    ) {
        discardExpiredPendingStates(now: now)
        guard !stillHasRecoveryForSession else { return }
        earlyStates = earlyStates.filter { key, _ in
            key.sessionIdentifier != sessionIdentifier
        }
    }

    mutating func keepOnlySession(_ sessionIdentifier: String?, now: Date) {
        discardExpiredPendingStates(now: now)
        guard let sessionIdentifier else {
            earlyStates.removeAll()
            pendingStates.removeAll()
            return
        }

        earlyStates = earlyStates.filter { key, _ in
            key.sessionIdentifier == sessionIdentifier
        }
        pendingStates = pendingStates.filter { key, _ in
            key.sessionIdentifier == sessionIdentifier
        }
    }

    private mutating func discardExpiredPendingStates(now: Date) {
        pendingStates = pendingStates.filter { _, state in
            state.expiresAt > now
        }
    }

    private static func consume(_ key: Key, from states: inout [Key: Int]) -> Bool {
        guard let count = states[key], count > 0 else { return false }
        if count == 1 {
            states[key] = nil
        } else {
            states[key] = count - 1
        }
        return true
    }

    private static func consume(_ key: Key, from states: inout [Key: PendingState]) -> Bool {
        guard var state = states[key], state.count > 0 else { return false }
        state.count -= 1
        states[key] = state.count == 0 ? nil : state
        return true
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

    private enum OwnerValidation: Equatable {
        case current
        case unavailable
        case mismatch
    }

    private let authenticationClient: any SyncAuthenticationClient
    private let syncScheduler: SyncScheduler
    private let hasActiveSession: @MainActor () -> Bool
    private let currentSessionIdentifier: @MainActor () -> String?
    private let expectedOwnerTokenIdentifier: @MainActor () -> String?
    private let now: @MainActor () -> Date
    private var activeRecovery: ActiveRecovery?
    private var inFlightRecoveries: [UUID: RecoveryMetadata] = [:]
    private var authenticatedStateCorrelation: AuthenticatedStateCorrelation

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
        currentSessionIdentifier: @MainActor @escaping () -> String? = { nil },
        expectedOwnerTokenIdentifier: @MainActor @escaping () -> String?,
        pendingAuthenticatedStateLifetime: TimeInterval = 5,
        now: @MainActor @escaping () -> Date = Date.init
    ) {
        self.authenticationClient = authenticationClient
        self.syncScheduler = syncScheduler
        self.hasActiveSession = hasActiveSession
        self.currentSessionIdentifier = currentSessionIdentifier
        self.expectedOwnerTokenIdentifier = expectedOwnerTokenIdentifier
        self.now = now
        self.authenticatedStateCorrelation = AuthenticatedStateCorrelation(
            pendingLifetime: pendingAuthenticatedStateLifetime
        )
    }

    func shouldActivateAuthenticatedState(
        ownerTokenIdentifier: String,
        sessionIdentifier: String?
    ) async -> Bool {
        guard hasActiveSession(), !syncScheduler.isDeletionModeEnabled else {
            return false
        }

        switch validateOwnerTokenIdentifier(ownerTokenIdentifier) {
        case .current:
            break
        case .unavailable:
            syncScheduler.currentOwnerTokenIdentifier = nil
            return false
        case .mismatch:
            await rejectInstalledAuthentication()
            return false
        }

        guard let sessionIdentifier else { return false }
        let key = AuthenticatedStateCorrelation.Key(
            ownerTokenIdentifier: ownerTokenIdentifier,
            sessionIdentifier: sessionIdentifier
        )
        let hasRecoveryForSession = inFlightRecoveries.values.contains { metadata in
            metadata.sessionIdentifier == sessionIdentifier
        }
        return !authenticatedStateCorrelation.shouldDefer(
            key: key,
            hasRecoveryForSession: hasRecoveryForSession,
            now: now()
        )
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
        authenticatedStateCorrelation.keepOnlySession(
            recoverySessionIdentifier,
            now: now()
        )
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
            guard case .success(let token) = result else {
                return
            }
            guard let ownerTokenIdentifier = await validatedRecoveredOwner(from: token) else {
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
        let key = AuthenticatedStateCorrelation.Key(
            ownerTokenIdentifier: ownerTokenIdentifier,
            sessionIdentifier: sessionIdentifier
        )
        authenticatedStateCorrelation.registerRecoveryAuthentication(key: key, now: now())
    }

    private func finishRecovery(_ recoveryID: UUID) {
        let sessionIdentifier = inFlightRecoveries.removeValue(forKey: recoveryID)?.sessionIdentifier
        guard let sessionIdentifier else { return }
        let stillHasRecoveryForSession = inFlightRecoveries.values.contains { metadata in
            metadata.sessionIdentifier == sessionIdentifier
        }
        authenticatedStateCorrelation.finishRecovery(
            sessionIdentifier: sessionIdentifier,
            stillHasRecoveryForSession: stillHasRecoveryForSession,
            now: now()
        )
    }

    private func validatedRecoveredOwner(from token: String) async -> String? {
        guard let ownerTokenIdentifier = ClerkJWTIdentityResolver.ownerTokenIdentifier(from: token),
              validateOwnerTokenIdentifier(ownerTokenIdentifier) == .current else {
            // loginFromCache installs the token on the shared Convex client before
            // returning it, so an unvalidated result must fail closed.
            await rejectInstalledAuthentication()
            return nil
        }
        return ownerTokenIdentifier
    }

    private func validateOwnerTokenIdentifier(_ ownerTokenIdentifier: String) -> OwnerValidation {
        guard let expectedOwnerTokenIdentifier = expectedOwnerTokenIdentifier() else {
            return .unavailable
        }
        return ownerTokenIdentifier == expectedOwnerTokenIdentifier ? .current : .mismatch
    }

    private func rejectInstalledAuthentication() async {
        syncScheduler.currentOwnerTokenIdentifier = nil
        await authenticationClient.logout()
    }
}
