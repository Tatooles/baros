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
            appSource.contains("activateOwnerForActiveClerkUserOrHideOwnerScopedData()"),
            "Restored active Clerk sessions should share the same guarded owner restore fallback."
        )
        XCTAssertTrue(
            appSource.contains("expectedClerkOwnerTokenIdentifier"),
            "Cached owner restoration must be bound to an issuer-scoped Clerk owner token."
        )
        XCTAssertFalse(
            appSource.contains("matchingOwnerSubject: activeClerkUserID"),
            "Production cached owner restoration must not use subject-only matching."
        )
        XCTAssertTrue(
            appSource.contains("syncScheduler.currentOwnerTokenIdentifier = nil"),
            "A mismatched or unavailable active Clerk user id must hide any stale selected owner."
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
                    syncScheduler.configure(modelContext: modelContainer.mainContext)
                    syncScheduler.enterSignedOutMode()
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

    func testUnauthenticatedConvexStateRestoresCachedOwnerBeforeSignedOutLocalMode() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertTrue(
            appSource.contains("if await restoreCachedSyncOwnerForActiveClerkSessionIfAvailable()"),
            "Convex unauthenticated startup must use the persisted owner when Clerk still has an active session."
        )
        XCTAssertTrue(
            appSource.contains("Clerk.shared.user?.id ?? Clerk.shared.session?.publicUserData?.userId"),
            "The active Clerk session fallback still needs Clerk's current user id to build an issuer-scoped owner token."
        )
        XCTAssertTrue(
            appSource.contains("activateOwnerForActiveClerkUserOrHideOwnerScopedData()"),
            "The unauthenticated active-Clerk fallback must use the guarded restore helper."
        )
        XCTAssertTrue(
            appSource.contains("activateValidatedOwnerTokenIdentifier(expectedClerkOwnerTokenIdentifier)"),
            "The unauthenticated restore fallback must validate the issuer-scoped owner token."
        )
        XCTAssertFalse(
            appSource.contains("matchingOwnerSubject: activeClerkUserID"),
            "Production active-Clerk restore must not expose same-subject data from another issuer."
        )
        XCTAssertTrue(
            appSource.contains("syncScheduler.currentOwnerTokenIdentifier = nil"),
            "A mismatched cached owner must leave owner-scoped data hidden while auth is unvalidated."
        )
        XCTAssertTrue(
            appSource.contains("syncScheduler.enterSignedOutMode()"),
            "Only the explicit signed-out startup path should clear the cached owner and seed ownerless defaults."
        )
        XCTAssertFalse(
            appSource.contains("""
                case .unauthenticated:
                    syncScheduler.currentOwnerTokenIdentifier = nil
                    syncScheduler.seedDefaultsForLocalMode()
"""),
            "Transient unauthenticated Convex state must not immediately clear the owner or seed ownerless defaults."
        )

        let unauthenticatedOffset = try XCTUnwrap(appSource.range(of: "case .unauthenticated:")).lowerBound
        let restoreOffset = try XCTUnwrap(
            appSource.range(of: "if await restoreCachedSyncOwnerForActiveClerkSessionIfAvailable()")
        ).lowerBound
        let signedOutOffset = try XCTUnwrap(
            appSource.range(
                of: "syncScheduler.enterSignedOutMode()",
                range: restoreOffset..<appSource.endIndex
            )
        ).lowerBound
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: unauthenticatedOffset),
            appSource.distance(from: appSource.startIndex, to: restoreOffset),
            "The unauthenticated branch should check for an active restored Clerk session before signed-out mode."
        )
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: restoreOffset),
            appSource.distance(from: appSource.startIndex, to: signedOutOffset),
            "Signed-out local seeding should be the fallback after cached owner restoration fails."
        )
    }

    func testActiveClerkRestoreMissDoesNotSeedOwnerlessDefaults() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertFalse(
            appSource.contains("restoreCachedOwnerForActiveClerkUserOrSeedLocalDefaults()"),
            "An active Clerk session must not fall back to ownerless local seeding."
        )
        XCTAssertTrue(
            appSource.contains("activateOwnerForActiveClerkUserOrHideOwnerScopedData()"),
            "An active Clerk restore miss should hide owner-scoped data until an exact owner is available."
        )
    }

    func testActiveClerkRestoreUsesCachedSessionOwnerTokenWhenAvailable() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertTrue(
            appSource.contains("private var activeClerkOwnerTokenIdentifier: String?"),
            "App startup should derive the full owner token from Clerk's cached session token when available."
        )
        XCTAssertTrue(
            appSource.contains("Clerk.shared.session?.lastActiveToken?.jwt"),
            "Offline owner restoration should use Clerk's cached session JWT to validate the issuer as well as subject."
        )
        XCTAssertTrue(
            appSource.contains("activateValidatedOwnerTokenIdentifier(activeClerkOwnerTokenIdentifier)"),
            "Cached owner restoration should prefer exact iss|sub matching when the active session token is available."
        )
    }

    func testActiveClerkRestoreFallbackBuildsIssuerScopedOwnerTokenFromConfiguration() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertTrue(
            appSource.contains("private var expectedClerkOwnerTokenIdentifier: String?"),
            "Active Clerk restore fallback should build a full owner token when no cached session JWT is available."
        )
        XCTAssertTrue(
            appSource.contains("ClerkJWTIdentityResolver.issuer(")
                && appSource.contains("fromPublishableKey: ClerkConfiguration.publishableKey"),
            "The fallback should derive the expected issuer from the configured Clerk publishable key."
        )
        XCTAssertTrue(
            appSource.contains("return \"\\(expectedClerkIssuer)|\\(activeClerkUserID)\""),
            "The fallback owner token should use the same iss|sub shape as decoded Clerk JWTs."
        )
    }

    func testAppRequestsSyncWhenSceneBecomesActive() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertTrue(
            appSource.contains("@Environment(\\.scenePhase)"),
            "The app must observe scenePhase so returning to the foreground can trigger sync."
        )
        XCTAssertTrue(
            appSource.contains(".onChange(of: scenePhase)"),
            "The root scene should respond to foreground lifecycle changes."
        )
        XCTAssertTrue(
            appSource.contains("newScenePhase == .active"),
            "Only foreground activation should trigger the lifecycle sync request."
        )
        XCTAssertTrue(
            appSource.contains("syncScheduler.requestSyncOnAppForeground()"),
            "Foreground activation should use the guarded scheduler trigger for signed-in, non-deletion-mode sync."
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
        var launchArguments = [
            "--uitest-reset-persistent-store",
            "--uitest-force-signed-out-auth",
        ]
"""),
            "Disk-backed reset launches should force signed-out auth so persisted tests cannot restore a real session."
        )
        XCTAssertTrue(
            uiTestSource.contains("""
        if extraArguments.isEmpty {
            launchArguments = ["--uitest-force-signed-out-auth"]
        } else {
"""),
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
