import Foundation

struct CurrentOwnerClerkSessionState: Equatable {
    let hasActiveSession: Bool
    let sessionIdentifier: String?
    let ownerTokenIdentifier: String?

    init(
        hasActiveSession: Bool,
        sessionIdentifier: String? = nil,
        ownerTokenIdentifier: String? = nil
    ) {
        self.hasActiveSession = hasActiveSession
        self.sessionIdentifier = sessionIdentifier
        self.ownerTokenIdentifier = ownerTokenIdentifier
    }
}

@MainActor
protocol CurrentOwnerClerkSessionProviding: AnyObject {
    var state: CurrentOwnerClerkSessionState { get }
    func waitUntilLoaded() async
}

enum CurrentOwnerConvexAuthenticationState: Equatable {
    case loading
    case unauthenticated
    case authenticated(token: String)
}

@MainActor
protocol CurrentOwnerAuthenticationClient: SyncAuthenticationClient {
    func observeAuthenticationStates(
        _ receive: @MainActor @escaping (CurrentOwnerConvexAuthenticationState) async -> Void
    ) async
}

@MainActor
@Observable
final class CurrentOwnerCoordinator {
    enum StartupMode: Equatable {
        case live
        case fixedOwner(String)
        case restoreCachedOwner(matchingSubject: String?)
        case signedOut
    }

    enum State: Equatable {
        case localOnly
        case resolving(ownerTokenIdentifier: String?)
        case active(ownerTokenIdentifier: String)
    }

    private(set) var state: State = .resolving(ownerTokenIdentifier: nil)

    private let authenticationClient: any CurrentOwnerAuthenticationClient
    private let syncScheduler: SyncScheduler
    private let clerkSessionProvider: any CurrentOwnerClerkSessionProviding
    private let startupMode: StartupMode
    private var hasStarted = false
    private var startupTask: Task<Void, Never>?
    private var authenticationStateTask: Task<Void, Never>?
    @ObservationIgnored
    private lazy var syncRecoveryCoordinator = SyncRecoveryCoordinator(
        authenticationClient: authenticationClient,
        syncScheduler: syncScheduler,
        hasActiveSession: { [weak self] in
            self?.clerkSessionProvider.state.hasActiveSession ?? false
        },
        currentSessionIdentifier: { [weak self] in
            self?.clerkSessionProvider.state.sessionIdentifier
        },
        expectedOwnerTokenIdentifier: { [weak self] in
            self?.clerkSessionProvider.state.ownerTokenIdentifier
        },
        onRecoveredOwner: { [weak self] ownerTokenIdentifier, trigger in
            self?.activateRecoveredOwner(
                ownerTokenIdentifier,
                trigger: trigger
            )
        }
    )

    init(
        authenticationClient: any CurrentOwnerAuthenticationClient,
        syncScheduler: SyncScheduler,
        clerkSessionProvider: any CurrentOwnerClerkSessionProviding,
        startupMode: StartupMode = .live
    ) {
        self.authenticationClient = authenticationClient
        self.syncScheduler = syncScheduler
        self.clerkSessionProvider = clerkSessionProvider
        self.startupMode = startupMode
        syncScheduler.pauseCloudSync()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard startupMode == .live else {
            startInTestMode(startupMode)
            return
        }

        authenticationStateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await authenticationClient.observeAuthenticationStates { [weak self] authenticationState in
                guard let self else { return }
                await handle(authenticationState)
            }
        }
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await recoverAuthentication(for: .startup)
        }
    }

    private func startInTestMode(_ startupMode: StartupMode) {
        switch startupMode {
        case .live:
            break
        case .fixedOwner(let ownerTokenIdentifier):
            syncScheduler.authorizeCloudSync()
            _ = syncScheduler.activateValidatedOwnerTokenIdentifier(ownerTokenIdentifier)
            state = .active(ownerTokenIdentifier: ownerTokenIdentifier)
        case .restoreCachedOwner(let matchingSubject):
            syncScheduler.pauseCloudSync()
            let didRestoreOwner: Bool
            if let matchingSubject {
                didRestoreOwner = syncScheduler.restoreLastKnownOwnerTokenIdentifier(
                    matchingOwnerSubject: matchingSubject
                )
            } else {
                syncScheduler.currentOwnerTokenIdentifier = nil
                didRestoreOwner = false
            }
            state = .resolving(
                ownerTokenIdentifier: didRestoreOwner
                    ? syncScheduler.currentOwnerTokenIdentifier
                    : nil
            )
        case .signedOut:
            enterLocalOnlyMode()
        }
    }

    func appDidEnterForeground() {
        requestSyncRecovery(for: .appForeground)
    }

    func retrySync() {
        requestSyncRecovery(for: .manualRetry)
    }

    func requestSyncRecovery(for trigger: SyncRecoveryCoordinator.Trigger) {
        guard startupMode == .live else {
            requestSyncInTestMode(for: trigger)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await recoverAuthentication(for: trigger)
        }
    }

    private func recoverAuthentication(for trigger: SyncRecoveryCoordinator.Trigger) async {
        await clerkSessionProvider.waitUntilLoaded()
        guard !Task.isCancelled else { return }
        enterLocalAccessStateFromClerk()
        guard clerkSessionProvider.state.hasActiveSession else { return }

        await syncRecoveryCoordinator.recoverAuthenticationAndRequestSync(for: trigger)
    }

    private func requestSyncInTestMode(for trigger: SyncRecoveryCoordinator.Trigger) {
        guard case .fixedOwner = startupMode else { return }
        switch trigger {
        case .startup:
            syncScheduler.requestSync()
        case .appForeground:
            break
        case .manualRetry:
            syncScheduler.retrySync()
        }
    }

    private func handle(_ authenticationState: CurrentOwnerConvexAuthenticationState) async {
        await clerkSessionProvider.waitUntilLoaded()
        guard !Task.isCancelled else { return }

        guard clerkSessionProvider.state.hasActiveSession else {
            enterLocalOnlyMode()
            return
        }

        let expectedOwnerTokenIdentifier = clerkSessionProvider.state.ownerTokenIdentifier
        if syncScheduler.currentOwnerTokenIdentifier != expectedOwnerTokenIdentifier {
            enterResolvingState(ownerTokenIdentifier: expectedOwnerTokenIdentifier)
        }

        switch authenticationState {
        case .loading, .unauthenticated:
            enterResolvingState(ownerTokenIdentifier: expectedOwnerTokenIdentifier)
        case .authenticated(let token):
            guard let ownerTokenIdentifier = ClerkJWTIdentityResolver.ownerTokenIdentifier(from: token) else {
                enterResolvingState(ownerTokenIdentifier: expectedOwnerTokenIdentifier)
                await authenticationClient.logout()
                return
            }
            guard ownerTokenIdentifier == expectedOwnerTokenIdentifier else {
                enterResolvingState(ownerTokenIdentifier: expectedOwnerTokenIdentifier)
                _ = await syncRecoveryCoordinator.shouldActivateAuthenticatedState(
                    ownerTokenIdentifier: ownerTokenIdentifier,
                    sessionIdentifier: clerkSessionProvider.state.sessionIdentifier
                )
                return
            }
            guard await syncRecoveryCoordinator.shouldActivateAuthenticatedState(
                      ownerTokenIdentifier: ownerTokenIdentifier,
                      sessionIdentifier: clerkSessionProvider.state.sessionIdentifier
                  ) else {
                return
            }

            activateValidatedOwner(ownerTokenIdentifier)
            syncScheduler.requestSync()
        }
    }

    private func enterLocalAccessStateFromClerk() {
        guard clerkSessionProvider.state.hasActiveSession else {
            enterLocalOnlyMode()
            return
        }

        enterResolvingState(ownerTokenIdentifier: clerkSessionProvider.state.ownerTokenIdentifier)
    }

    private func enterResolvingState(ownerTokenIdentifier: String?) {
        syncScheduler.pauseCloudSync()
        if let ownerTokenIdentifier {
            _ = syncScheduler.activateValidatedOwnerTokenIdentifier(ownerTokenIdentifier)
        } else {
            syncScheduler.currentOwnerTokenIdentifier = nil
        }
        state = .resolving(ownerTokenIdentifier: ownerTokenIdentifier)
    }

    private func enterLocalOnlyMode() {
        syncScheduler.pauseCloudSync()
        syncScheduler.enterSignedOutMode()
        state = .localOnly
    }

    private func activateValidatedOwner(_ ownerTokenIdentifier: String) {
        syncScheduler.authorizeCloudSync()
        _ = syncScheduler.activateValidatedOwnerTokenIdentifier(ownerTokenIdentifier)
        state = .active(ownerTokenIdentifier: ownerTokenIdentifier)
    }

    private func activateRecoveredOwner(
        _ ownerTokenIdentifier: String,
        trigger: SyncRecoveryCoordinator.Trigger
    ) {
        activateValidatedOwner(ownerTokenIdentifier)
        switch trigger {
        case .startup:
            syncScheduler.requestSync()
        case .appForeground:
            syncScheduler.requestSyncOnAppForeground()
        case .manualRetry:
            syncScheduler.retrySync()
        }
    }
}
