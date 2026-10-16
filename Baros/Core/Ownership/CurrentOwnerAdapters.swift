import ClerkKit
@preconcurrency import ConvexMobile
import Foundation

struct CurrentOwnerLaunchConfiguration {
    let startupMode: CurrentOwnerCoordinator.StartupMode
    let fixedOwnerTokenIdentifier: String?
    let observesNetworkRecovery: Bool

    init(arguments: [String]) {
        let fixedOwnerTokenIdentifier = Self.argument(
            after: "--uitest-sync-owner",
            in: arguments
        )
        self.fixedOwnerTokenIdentifier = fixedOwnerTokenIdentifier

        if let fixedOwnerTokenIdentifier {
            startupMode = .fixedOwner(fixedOwnerTokenIdentifier)
        } else if arguments.contains("--uitest-restore-cached-sync-owner") {
            startupMode = .restoreCachedOwner(
                matchingSubject: Self.argument(
                    after: "--uitest-restore-cached-sync-owner-subject",
                    in: arguments
                )
            )
        } else if arguments.contains("--uitest-force-signed-out-auth") {
            startupMode = .signedOut
        } else {
            startupMode = .live
        }
        observesNetworkRecovery = startupMode == .live
            && !arguments.contains(where: { $0.hasPrefix("--uitest-") })
    }

    private static func argument(after flag: String, in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
    }
}

@MainActor
final class ClerkCurrentOwnerSessionProvider: CurrentOwnerClerkSessionProviding {
    var state: CurrentOwnerClerkSessionState {
        guard Clerk.shared.session?.status == .active else {
            return CurrentOwnerClerkSessionState(hasActiveSession: false)
        }

        return CurrentOwnerClerkSessionState(
            hasActiveSession: true,
            sessionIdentifier: Clerk.shared.session?.id,
            ownerTokenIdentifier: activeTokenOwnerTokenIdentifier
                ?? expectedOwnerTokenIdentifier
        )
    }

    func waitUntilLoaded() async {
        while !Task.isCancelled, !Clerk.shared.isLoaded {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func observeSessionStates(
        _ receive: @MainActor @escaping (CurrentOwnerClerkSessionState) -> Void
    ) async {
        // Subscribe before waiting for loading, independently of the Convex
        // bridge's token requests, so a confirmed identity change cannot wait
        // behind network authentication.
        let events = Clerk.shared.auth.events
        await waitUntilLoaded()
        guard !Task.isCancelled else { return }
        receive(state)
        for await event in events {
            guard !Task.isCancelled else { return }
            if case .sessionChanged = event {
                receive(state)
            }
        }
    }

    private var activeTokenOwnerTokenIdentifier: String? {
        guard let jwt = Clerk.shared.session?.lastActiveToken?.jwt else {
            return nil
        }
        return ClerkJWTIdentityResolver.ownerTokenIdentifier(from: jwt)
    }

    private var expectedOwnerTokenIdentifier: String? {
        let userID = Clerk.shared.user?.id
            ?? Clerk.shared.session?.publicUserData?.userId
        guard let userID,
              let issuer = ClerkJWTIdentityResolver.issuer(
                  fromPublishableKey: ClerkConfiguration.publishableKey
              ) else {
            return nil
        }
        return "\(issuer)|\(userID)"
    }
}

@MainActor
final class ConvexCurrentOwnerAuthenticationClient: CurrentOwnerAuthenticationClient {
    private let client: ConvexClientWithAuth<String>

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    func observeAuthenticationStates(
        _ receive: @MainActor @escaping (CurrentOwnerConvexAuthenticationState) async -> Void
    ) async {
        for await state in client.authState.values {
            switch state {
            case .loading:
                await receive(.loading)
            case .unauthenticated:
                await receive(.unauthenticated)
            case .authenticated(let token):
                await receive(.authenticated(token: token))
            }
        }
    }

    func loginFromCache() async -> Result<String, Error> {
        await client.loginFromCache()
    }

    func logout() async {
        await client.logout()
    }
}

#if DEBUG
/// Simulates Clerk session events while cloud authentication stays pending.
/// Used only with --uitest-clerk-session-control; it never contacts Clerk or Convex.
@MainActor
final class CurrentOwnerClerkSessionUITestProvider: CurrentOwnerClerkSessionProviding {
    private(set) var state: CurrentOwnerClerkSessionState
    private let states: AsyncStream<CurrentOwnerClerkSessionState>
    private let continuation: AsyncStream<CurrentOwnerClerkSessionState>.Continuation

    init(ownerTokenIdentifier: String) {
        state = CurrentOwnerClerkSessionState(
            hasActiveSession: true,
            sessionIdentifier: "uitest_session_a",
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        let stream = AsyncStream<CurrentOwnerClerkSessionState>.makeStream()
        states = stream.stream
        continuation = stream.continuation
    }

    func waitUntilLoaded() async {}

    func observeSessionStates(
        _ receive: @MainActor @escaping (CurrentOwnerClerkSessionState) -> Void
    ) async {
        receive(state)
        for await _ in states {
            guard !Task.isCancelled else { return }
            receive(state)
        }
    }

    func signOut() {
        state = CurrentOwnerClerkSessionState(hasActiveSession: false)
        continuation.yield(state)
    }

    func switchAccount() {
        state = CurrentOwnerClerkSessionState(
            hasActiveSession: true,
            sessionIdentifier: "uitest_session_b",
            ownerTokenIdentifier: "issuer|uitest_replacement_owner"
        )
        continuation.yield(state)
    }
}

@MainActor
final class PendingCurrentOwnerUITestAuthenticationClient: CurrentOwnerAuthenticationClient {
    func observeAuthenticationStates(
        _ receive: @MainActor @escaping (CurrentOwnerConvexAuthenticationState) async -> Void
    ) async {
        await receive(.loading)
    }

    func loginFromCache() async -> Result<String, Error> {
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch {
            return .failure(error)
        }
        return .failure(CancellationError())
    }

    func logout() async {}
}
#endif
