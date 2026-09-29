import XCTest
import ConvexMobile
@testable import Baros

final class ConvexConfigurationTests: XCTestCase {
    func testDeploymentURLUsesHTTPSConvexCloudHost() {
        XCTAssertEqual(ConvexConfiguration.deploymentURL.scheme, "https")
        XCTAssertEqual(ConvexConfiguration.deploymentURL.host, "glad-cow-603.convex.cloud")
    }

    func testDeploymentURLStringHasNoTrailingSlash() {
        XCTAssertEqual(
            ConvexConfiguration.deploymentURLString,
            "https://glad-cow-603.convex.cloud"
        )
    }

    @MainActor
    func testAuthenticatedClientFactoryReusesSingleInstance() {
        let firstClient = ConvexClientFactory.makeAuthenticatedClient()
        let secondClient = ConvexClientFactory.makeAuthenticatedClient()

        XCTAssertTrue(firstClient === secondClient)
    }

    @MainActor
    func testConvexLogoutWrapperDoesNotSignOutItsClerkProvider() async throws {
        let clerkProvider = StubClerkConvexAuthProvider()
        let provider = ClerkRetainingConvexAuthProvider(clerkProvider: clerkProvider)

        try await provider.logout()

        XCTAssertEqual(clerkProvider.logoutCallCount, 0)
    }

    func testAuthenticatedClientFactoryUsesClerkConvexProvider() throws {
        let factorySource = try sourceFileContents("Baros/Core/Sync/ConvexClientFactory.swift")

        XCTAssertTrue(
            factorySource.contains("ClerkConvexAuthProvider()"),
            "Convex auth should use Clerk's Swift integration package."
        )
        XCTAssertFalse(
            factorySource.contains("ClerkConvexTemplateAuthProvider"),
            "Do not bypass the official Clerk Convex provider with a local template-specific provider."
        )
    }

    func testConvexAuthConfigRequiresConvexAudience() throws {
        let authConfigSource = try sourceFileContents("convex/auth.config.ts")

        XCTAssertTrue(
            authConfigSource.contains(#"applicationID: "convex""#),
            "Production Convex auth must preserve audience verification for Clerk JWTs."
        )
        XCTAssertFalse(
            authConfigSource.contains(#"type: "customJwt""#),
            "Clerk Convex auth should use the standard OIDC provider config."
        )
    }

    private func sourceFileContents(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: projectRootURL.appending(path: relativePath), encoding: .utf8)
    }
}

@MainActor
private final class StubClerkConvexAuthProvider: ClerkConvexAuthenticating {
    private(set) var logoutCallCount = 0

    func login(
        onIdToken: @Sendable @escaping (String?) -> Void
    ) async throws -> String {
        "token"
    }

    func loginFromCache(
        onIdToken: @Sendable @escaping (String?) -> Void
    ) async throws -> String {
        "token"
    }

    func logout() async throws {
        logoutCallCount += 1
    }
}
