import ClerkConvex
import ConvexMobile

@MainActor
enum ConvexClientFactory {
    private static let authenticatedClient = ConvexClientWithAuth(
        deploymentUrl: ConvexConfiguration.deploymentURLString,
        authProvider: ClerkConvexAuthProvider()
    )

    static func makeAuthenticatedClient() -> ConvexClientWithAuth<String> {
        authenticatedClient
    }
}
