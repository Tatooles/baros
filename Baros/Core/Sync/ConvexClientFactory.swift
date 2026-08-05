import ClerkConvex
@preconcurrency import ConvexMobile

@MainActor
protocol ClerkConvexAuthenticating: AnyObject {
    func login(
        onIdToken: @Sendable @escaping (String?) -> Void
    ) async throws -> String
    func loginFromCache(
        onIdToken: @Sendable @escaping (String?) -> Void
    ) async throws -> String
    func logout() async throws
}

extension ClerkConvexAuthProvider: ClerkConvexAuthenticating {}

/// Lets Convex clear only its installed authentication. Clerk remains the
/// authority for the signed-in account and is signed out through Clerk UI flows.
@MainActor
final class ClerkRetainingConvexAuthProvider: AuthProvider {
    typealias T = String

    private let clerkProvider: any ClerkConvexAuthenticating

    init(clerkProvider: any ClerkConvexAuthenticating) {
        self.clerkProvider = clerkProvider
    }

    func login(
        onIdToken: @Sendable @escaping (String?) -> Void
    ) async throws -> String {
        try await clerkProvider.login(onIdToken: onIdToken)
    }

    func loginFromCache(
        onIdToken: @Sendable @escaping (String?) -> Void
    ) async throws -> String {
        try await clerkProvider.loginFromCache(onIdToken: onIdToken)
    }

    func logout() async throws {
        // ConvexClientWithAuth clears its own auth state after this returns.
        // Do not delegate: ClerkConvexAuthProvider.logout signs out Clerk too.
    }

    nonisolated func extractIdToken(from authResult: String) -> String {
        authResult
    }
}

@MainActor
enum ConvexClientFactory {
    private static let authenticatedClient: ConvexClientWithAuth<String> = {
        let clerkProvider = ClerkConvexAuthProvider()
        let client = ConvexClientWithAuth(
            deploymentUrl: ConvexConfiguration.deploymentURLString,
            authProvider: ClerkRetainingConvexAuthProvider(
                clerkProvider: clerkProvider
            )
        )
        clerkProvider.bind(client: client)
        return client
    }()

    static func makeAuthenticatedClient() -> ConvexClientWithAuth<String> {
        authenticatedClient
    }
}
