import XCTest
@testable import Baros
@testable import BarosCore

final class ClerkConfigurationTests: XCTestCase {
    func testDebugBuildUsesDevelopmentBundleIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.kevintatooles.LiftingLog.dev")
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            "Baros Dev"
        )
    }

    func testAppBundleIncludesEnvironmentConfigurationKeys() {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]

        XCTAssertNotNil(infoDictionary["BarosEnvironment"])
        XCTAssertNotNil(infoDictionary["ClerkPublishableKey"])
        XCTAssertNotNil(infoDictionary["ClerkAssociatedDomain"])
        XCTAssertNotNil(infoDictionary["ConvexDeploymentURL"])
        XCTAssertNotNil(infoDictionary["CFBundleShortVersionString"])
        XCTAssertNotNil(infoDictionary["CFBundleVersion"])
    }

    func testAppBundleUsesCanonicalSimulatorPlatformValue() {
        let supportedPlatforms = Bundle.main.object(forInfoDictionaryKey: "CFBundleSupportedPlatforms") as? [String]

        XCTAssertEqual(supportedPlatforms, ["iPhoneSimulator"])
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
