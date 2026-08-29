import XCTest
@testable import Baros

final class AppInitializationOrderTests: XCTestCase {
    func testConvexClientIsInitializedAfterClerkConfiguration() throws {
        let appSource = try sourceFileContents("Baros/App/BarosApp.swift")

        XCTAssertFalse(
            appSource.contains("@State private var convexClient = ConvexClientFactory.makeAuthenticatedClient()"),
            "ConvexClientWithAuth must not be created before BarosApp.init() calls Clerk.configure."
        )

        let clerkConfigureOffset = try XCTUnwrap(appSource.range(of: "Clerk.configure")).lowerBound
        let convexClientOffset = try XCTUnwrap(
            appSource.range(of: "convexClient = ConvexClientFactory.makeAuthenticatedClient()")
        ).lowerBound

        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: clerkConfigureOffset),
            appSource.distance(from: appSource.startIndex, to: convexClientOffset),
            "Clerk.configure must run before the Clerk-backed Convex auth provider is created."
        )
    }

    func testSentryBoundaryStartsEarlyAndIsSharedBySyncOrchestration() throws {
        let appSource = try sourceFileContents("Baros/App/BarosApp.swift")

        let sentryStartOffset = try XCTUnwrap(
            appSource.range(of: "let syncObservability = SentryRuntime.startIfEnabled()")
        ).lowerBound
        let clerkConfigureOffset = try XCTUnwrap(appSource.range(of: "Clerk.configure")).lowerBound
        let persistenceOffset = try XCTUnwrap(
            appSource.range(of: "ModelContainerFactory.makeModelContainer")
        ).lowerBound

        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: sentryStartOffset),
            appSource.distance(from: appSource.startIndex, to: clerkConfigureOffset)
        )
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: sentryStartOffset),
            appSource.distance(from: appSource.startIndex, to: persistenceOffset)
        )
        XCTAssertTrue(appSource.contains("SyncScheduler(observability: syncObservability)"))
        XCTAssertTrue(appSource.contains("observability: syncObservability"))
        XCTAssertFalse(appSource.contains("import Sentry"))
    }

    func testUITestHelpersForceSignedOutAuthByDefault() throws {
        let uiTestSource = try sourceFileContents("BarosUITests/BarosUITests.swift")

        XCTAssertTrue(
            uiTestSource.contains(#"let authArguments = extraArguments.contains("--uitest-force-signed-in-auth")"#)
                && uiTestSource.contains(#": ["--uitest-force-signed-out-auth"]"#),
            "Shared UI test launches should force signed-out auth unless explicitly overridden."
        )
        XCTAssertTrue(
            uiTestSource.contains("""
        var launchArguments = [
            "--uitest-reset-persistent-store",
            "--uitest-force-signed-out-auth",
""")
        )
        XCTAssertTrue(
            uiTestSource.contains("""
        if extraArguments.isEmpty {
            launchArguments = ["--uitest-force-signed-out-auth"]
        } else {
""")
        )
    }

    private func sourceFileContents(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: projectRootURL.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
