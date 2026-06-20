import ConvexMobile

@MainActor
enum ConvexClientFactory {
    private static let authenticatedClient: ConvexClientWithAuth<String> = {
        let authProvider = ClerkConvexTemplateAuthProvider(jwtTemplate: "convex")
        let client = ConvexClientWithAuth<String>(
            deploymentUrl: ConvexConfiguration.deploymentURLString,
            authProvider: authProvider
        )
        authProvider.bind(client: client)
        return client
    }()

    static func makeAuthenticatedClient() -> ConvexClientWithAuth<String> {
        authenticatedClient
    }
}
