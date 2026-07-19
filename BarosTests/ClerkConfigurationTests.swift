import XCTest
@testable import Baros

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

    func testAppBuildInfoFormatsVersionAndBuildFromInfoDictionary() {
        let buildInfo = AppBuildInfo(infoDictionary: [
            "CFBundleDisplayName": "Baros Dev",
            "CFBundleIdentifier": "com.kevintatooles.LiftingLog.dev",
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "45",
            "BarosEnvironment": "Development",
        ])

        XCTAssertEqual(buildInfo.displayName, "Baros Dev")
        XCTAssertEqual(buildInfo.bundleIdentifier, "com.kevintatooles.LiftingLog.dev")
        XCTAssertEqual(buildInfo.version, "1.2")
        XCTAssertEqual(buildInfo.buildNumber, "45")
        XCTAssertEqual(buildInfo.environmentName, "Development")
        XCTAssertEqual(buildInfo.versionAndBuild, "1.2 (45)")
        XCTAssertEqual(buildInfo.settingsVersionText, "Version 1.2 (45)")
    }

    func testAppSourceMetadataFormatsCleanBranchAndCommit() {
        let metadata = AppSourceMetadata(
            branch: "codex/copy-app-info-feedback",
            shortCommit: "1b92aab",
            hasLocalChanges: false,
            builtAt: "2026-06-27 16:18:00 -0500",
            configuration: "Debug"
        )

        XCTAssertEqual(metadata.sourceDescription, "codex/copy-app-info-feedback @ 1b92aab")
    }

    func testAppSourceMetadataIncludesLocalChangesWhenDirty() {
        let metadata = AppSourceMetadata(
            branch: "codex/copy-app-info-feedback",
            shortCommit: "1b92aab",
            hasLocalChanges: true,
            builtAt: "2026-06-27 16:18:00 -0500",
            configuration: "Debug"
        )

        XCTAssertEqual(metadata.sourceDescription, "codex/copy-app-info-feedback @ 1b92aab + local changes")
    }

    func testAppSourceMetadataCanDescribeUncommittedBuildWithoutCommit() {
        let metadata = AppSourceMetadata(
            branch: "codex/copy-app-info-feedback",
            shortCommit: "",
            hasLocalChanges: true,
            builtAt: "2026-06-27 16:18:00 -0500",
            configuration: "Debug"
        )

        XCTAssertEqual(metadata.sourceDescription, "codex/copy-app-info-feedback + local changes")
    }

    func testAppBuildInfoSupportSummaryOmitsSensitiveBackendConfiguration() {
        let buildInfo = AppBuildInfo(infoDictionary: [
            "CFBundleDisplayName": "Baros",
            "CFBundleIdentifier": "com.kevintatooles.LiftingLog",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "123",
            "BarosEnvironment": "Production",
            "ClerkPublishableKey": "pk_live_sensitive",
            "ClerkAssociatedDomain": "webcredentials:clerk.auth.liftinglog.app",
            "ConvexDeploymentURL": "https://sensible-reindeer-16.convex.cloud",
        ])

        let summary = buildInfo.supportSummary(
            device: DeviceSystemInfo(
                model: "iPhone",
                systemName: "iOS",
                systemVersion: "26.0"
            )
        )

        XCTAssertTrue(summary.contains("App: Baros"))
        XCTAssertTrue(summary.contains("Version: 1.0 (123)"))
        XCTAssertTrue(summary.contains("Environment: Production"))
        XCTAssertTrue(summary.contains("Bundle ID: com.kevintatooles.LiftingLog"))
        XCTAssertTrue(summary.contains("Device: iPhone"))
        XCTAssertTrue(summary.contains("OS: iOS 26.0"))
        XCTAssertFalse(summary.contains("pk_live_sensitive"))
        XCTAssertFalse(summary.contains("clerk.auth.liftinglog.app"))
        XCTAssertFalse(summary.contains("sensible-reindeer-16.convex.cloud"))
    }

    func testCopyAppInfoFeedbackStateDefaultsToCopyPrompt() {
        XCTAssertEqual(CopyAppInfoFeedbackState.idle.title, "Copy App Info")
        XCTAssertEqual(CopyAppInfoFeedbackState.idle.systemImage, "doc.on.doc")
    }

    func testCopyAppInfoFeedbackStateShowsCopiedConfirmation() {
        XCTAssertEqual(CopyAppInfoFeedbackState.copied.title, "Copied")
        XCTAssertEqual(CopyAppInfoFeedbackState.copied.systemImage, "checkmark")
    }

    func testAppBundleUsesCanonicalSimulatorPlatformValue() {
        let supportedPlatforms = Bundle.main.object(forInfoDictionaryKey: "CFBundleSupportedPlatforms") as? [String]

        XCTAssertEqual(supportedPlatforms, ["iPhoneSimulator"])
    }

    func testDevelopmentInfoDictionaryBuildsDevelopmentConfiguration() {
        let configuration = AppEnvironmentConfiguration(infoDictionary: [
            "BarosEnvironment": "Development",
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
            "BarosEnvironment": "Production",
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
