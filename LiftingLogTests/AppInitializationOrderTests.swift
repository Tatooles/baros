import XCTest
@testable import LiftingLog

final class AppInitializationOrderTests: XCTestCase {
    func testConvexClientIsInitializedAfterClerkConfiguration() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertFalse(
            appSource.contains("@State private var convexClient = ConvexClientFactory.makeAuthenticatedClient()"),
            "ConvexClientWithAuth must not be created before LiftingLogApp.init() calls Clerk.configure."
        )

        let clerkConfigureOffset = try XCTUnwrap(appSource.range(of: "Clerk.configure")).lowerBound
        let convexClientOffset = try XCTUnwrap(appSource.range(of: "convexClient = ConvexClientFactory.makeAuthenticatedClient()")).lowerBound

        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: clerkConfigureOffset),
            appSource.distance(from: appSource.startIndex, to: convexClientOffset),
            "Clerk.configure must run before ConvexClientFactory creates the Clerk-backed Convex auth provider."
        )
    }

    func testRestoredClerkSessionRetriesConvexCacheLoginAfterClerkLoads() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertTrue(
            appSource.contains("await syncConvexAuthFromRestoredClerkSessionIfAvailable()"),
            "App startup must retry Convex auth for already-restored Clerk sessions before observing sync state."
        )
        XCTAssertTrue(
            appSource.contains("Clerk.shared.session?.status == .active"),
            "The retry must be limited to restored active Clerk sessions."
        )
        XCTAssertTrue(
            appSource.contains("Clerk.shared.isLoaded"),
            "Convex cache login must wait until Clerk can issue session tokens."
        )
        let waitForClerkOffset = try XCTUnwrap(appSource.range(of: "await waitUntilClerkIsLoaded()")).lowerBound
        let activeSessionOffset = try XCTUnwrap(appSource.range(of: "guard Clerk.shared.session?.status == .active")).lowerBound
        let loginFromCacheOffset = try XCTUnwrap(appSource.range(of: "await convexClient.loginFromCache()")).lowerBound
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: waitForClerkOffset),
            appSource.distance(from: appSource.startIndex, to: activeSessionOffset),
            "Startup retry must wait for Clerk to load before deciding whether a restored active session exists."
        )
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: activeSessionOffset),
            appSource.distance(from: appSource.startIndex, to: loginFromCacheOffset),
            "Convex cache login should run only after Clerk has loaded an active restored session."
        )
        XCTAssertTrue(
            appSource.contains("await convexClient.loginFromCache()"),
            "Restored Clerk sessions need an explicit Convex cache login because no sessionChanged event is emitted."
        )
    }

    func testRestoredClerkSessionWaitHasNoFixedRetryDeadline() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertFalse(
            appSource.contains("for _ in 0..<50"),
            "Restored Clerk session sync must not give up after a fixed retry cap; slow Clerk startup should still reach Convex cache login."
        )
        XCTAssertTrue(
            appSource.contains("Task.isCancelled"),
            "An unbounded Clerk load wait must exit when the startup task is cancelled."
        )
    }

    func testForcedSignedOutUITestModeSkipsRestoredAuthSyncStartup() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertTrue(
            appSource.contains("let uiTestForcesSignedOutAuth: Bool"),
            "App startup should store the forced signed-out UI test mode once from launch arguments."
        )
        XCTAssertTrue(
            appSource.contains("\"--uitest-force-signed-out-auth\""),
            "Forced signed-out UI tests need an app-level launch argument, not only a profile-card display override."
        )
        XCTAssertTrue(
            appSource.contains("if uiTestForcesSignedOutAuth"),
            "Forced signed-out UI tests must skip restored Clerk/Convex sync startup."
        )
        XCTAssertTrue(
            appSource.contains("""
                if uiTestForcesSignedOutAuth {
                    syncScheduler.currentOwnerTokenIdentifier = nil
                    syncScheduler.configure(modelContext: modelContainer.mainContext)
                    syncScheduler.seedDefaultsForLocalMode()
                    return
                }
"""),
            "Forced signed-out UI tests must configure the scheduler model context before seeding local defaults."
        )

        let syncOwnerOffset = try XCTUnwrap(appSource.range(of: "if let uiTestSyncOwner")).lowerBound
        let forcedSignedOutOffset = try XCTUnwrap(appSource.range(of: "if uiTestForcesSignedOutAuth")).lowerBound
        let configureSyncOffset = try XCTUnwrap(appSource.range(of: "configureSyncIfNeeded()")).lowerBound

        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: syncOwnerOffset),
            appSource.distance(from: appSource.startIndex, to: forcedSignedOutOffset),
            "Explicit sync-owner UI tests should still be able to exercise sync behavior."
        )
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: forcedSignedOutOffset),
            appSource.distance(from: appSource.startIndex, to: configureSyncOffset),
            "Forced signed-out UI tests should return before normal sync startup can restore auth."
        )
    }

    func testUITestHelpersForceSignedOutAuthByDefault() throws {
        let uiTestSource = try sourceFileContents("LiftingLogUITests/LiftingLogUITests.swift")

        XCTAssertTrue(
            uiTestSource.contains(#"let authArguments = extraArguments.contains("--uitest-force-signed-in-auth")"#)
                && uiTestSource.contains(#": ["--uitest-force-signed-out-auth"]"#),
            "Shared UI test app launches should force signed-out auth unless a test explicitly asks for the signed-in override."
        )
        XCTAssertTrue(
            uiTestSource.contains("""
        app.launchArguments = [
            "--uitest-reset-persistent-store",
            "--uitest-force-signed-out-auth",
        ]
"""),
            "Disk-backed reset launches should force signed-out auth so persisted tests cannot restore a real session."
        )
        XCTAssertTrue(
            uiTestSource.contains(#"app.launchArguments = ["--uitest-force-signed-out-auth"]"#),
            "Disk-backed relaunches should force signed-out auth so relaunch tests cannot restore a real session."
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
