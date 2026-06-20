import XCTest
import ConvexMobile
@testable import LiftingLog

final class ConvexConfigurationTests: XCTestCase {
    func testDevelopmentInfoDictionaryBuildsDevelopmentConvexURL() {
        let configuration = AppEnvironmentConfiguration(infoDictionary: [
            "LiftingLogEnvironment": "Development",
            "ClerkPublishableKey": "pk_test_Z2xhZC1rcmlsbC0yMi5jbGVyay5hY2NvdW50cy5kZXYk",
            "ClerkAssociatedDomain": "webcredentials:glad-krill-22.clerk.accounts.dev",
            "ConvexDeploymentURL": "https://glad-cow-603.convex.cloud",
        ])

        XCTAssertEqual(configuration.convexDeploymentURL.scheme, "https")
        XCTAssertEqual(configuration.convexDeploymentURL.host, "glad-cow-603.convex.cloud")
        XCTAssertEqual(
            configuration.convexDeploymentURL.absoluteString,
            "https://glad-cow-603.convex.cloud"
        )
    }

    func testProductionInfoDictionaryBuildsProductionConvexURL() {
        let configuration = AppEnvironmentConfiguration(infoDictionary: [
            "LiftingLogEnvironment": "Production",
            "ClerkPublishableKey": "pk_live_Y2xlcmsuYXV0aC5saWZ0aW5nbG9nLmFwcCQ",
            "ClerkAssociatedDomain": "webcredentials:clerk.auth.liftinglog.app",
            "ConvexDeploymentURL": "https://sensible-reindeer-16.convex.cloud",
        ])

        XCTAssertEqual(configuration.convexDeploymentURL.scheme, "https")
        XCTAssertEqual(configuration.convexDeploymentURL.host, "sensible-reindeer-16.convex.cloud")
        XCTAssertEqual(
            configuration.convexDeploymentURL.absoluteString,
            "https://sensible-reindeer-16.convex.cloud"
        )
    }

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

    func testAuthenticatedClientFactoryRequestsConvexJWTTemplate() throws {
        let factorySource = try sourceFileContents("LiftingLog/Core/Sync/ConvexClientFactory.swift")

        XCTAssertTrue(
            factorySource.contains(#"ClerkConvexTemplateAuthProvider(jwtTemplate: "convex")"#),
            "Convex auth must request the Clerk JWT template that emits aud=convex."
        )
    }

    func testConvexAuthConfigRequiresConvexAudience() throws {
        let authConfigSource = try sourceFileContents("convex/auth.config.ts")

        XCTAssertTrue(
            authConfigSource.contains(#"applicationID: "convex""#),
            "Production Convex auth must preserve audience verification for Clerk JWTs."
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
