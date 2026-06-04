import ClerkConvex
import ConvexMobile

@MainActor
enum ConvexClientFactory {
    static func makeAuthenticatedClient() -> ConvexClientWithAuth<String> {
        ConvexClientWithAuth(
            deploymentUrl: ConvexConfiguration.deploymentURLString,
            authProvider: ClerkConvexAuthProvider()
        )
    }
}
