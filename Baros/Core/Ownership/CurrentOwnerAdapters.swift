import ClerkKit
@preconcurrency import ConvexMobile
import Foundation

struct CurrentOwnerLaunchConfiguration {
    let startupMode: CurrentOwnerCoordinator.StartupMode
    let fixedOwnerTokenIdentifier: String?

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
