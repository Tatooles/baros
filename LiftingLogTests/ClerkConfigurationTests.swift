import XCTest
@testable import LiftingLog

final class ClerkConfigurationTests: XCTestCase {
    func testDebugBuildUsesDevelopmentBundleIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.kevintatooles.LiftingLog.dev")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            "Lifting Log Dev"
        )
    }

    func testAppBundleIncludesEnvironmentConfigurationKeys() {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]

        XCTAssertNotNil(infoDictionary["LiftingLogEnvironment"])
        XCTAssertNotNil(infoDictionary["ClerkPublishableKey"])
        XCTAssertNotNil(infoDictionary["ClerkAssociatedDomain"])
        XCTAssertNotNil(infoDictionary["ConvexDeploymentURL"])
        XCTAssertNotNil(infoDictionary["CFBundleShortVersionString"])
        XCTAssertNotNil(infoDictionary["CFBundleVersion"])
    }

    func testDevelopmentInfoDictionaryBuildsDevelopmentConfiguration() {
        let configuration = AppEnvironmentConfiguration(infoDictionary: [
            "LiftingLogEnvironment": "Development",
            "ClerkPublishableKey": "pk_test_Z2xhZC1rcmlsbC0yMi5jbGVyay5hY2NvdW50cy5kZXYk",
            "ClerkAssociatedDomain": "webcredentials:glad-krill-22.clerk.accounts.dev",
            "ConvexDeploymentURL": "https://glad-cow-603.convex.cloud",
        ])

        XCTAssertEqual(configuration.environment, .development)
        XCTAssertEqual(
            configuration.clerkPublishableKey,
            "pk_test_Z2xhZC1rcmlsbC0yMi5jbGVyay5hY2NvdW50cy5kZXYk"
        )
        XCTAssertEqual(
            configuration.clerkAssociatedDomain,
            "webcredentials:glad-krill-22.clerk.accounts.dev"
        )
    }

    func testProductionInfoDictionaryBuildsProductionConfiguration() {
        let configuration = AppEnvironmentConfiguration(infoDictionary: [
            "LiftingLogEnvironment": "Production",
            "ClerkPublishableKey": "pk_live_Y2xlcmsuYXV0aC5saWZ0aW5nbG9nLmFwcCQ",
            "ClerkAssociatedDomain": "webcredentials:clerk.auth.liftinglog.app",
            "ConvexDeploymentURL": "https://sensible-reindeer-16.convex.cloud",
        ])

        XCTAssertEqual(configuration.environment, .production)
        XCTAssertEqual(
            configuration.clerkPublishableKey,
            "pk_live_Y2xlcmsuYXV0aC5saWZ0aW5nbG9nLmFwcCQ"
        )
        XCTAssertEqual(
            configuration.clerkAssociatedDomain,
            "webcredentials:clerk.auth.liftinglog.app"
        )
    }

    func testDevelopmentPublishableKeyUsesTestPrefix() {
        XCTAssertTrue(ClerkConfiguration.publishableKey.hasPrefix("pk_test_"))
    }

    func testAssociatedDomainUsesWebCredentialsWithoutScheme() {
        XCTAssertEqual(
            ClerkConfiguration.associatedDomain,
            "webcredentials:glad-krill-22.clerk.accounts.dev"
        )
        XCTAssertFalse(ClerkConfiguration.associatedDomain.contains("https://"))
    }
}
