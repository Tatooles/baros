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
        let isLoadedOffset = try XCTUnwrap(appSource.range(of: "if Clerk.shared.isLoaded")).lowerBound
        let activeSessionOffset = try XCTUnwrap(appSource.range(of: "guard Clerk.shared.session?.status == .active")).lowerBound
        let loginFromCacheOffset = try XCTUnwrap(appSource.range(of: "await convexClient.loginFromCache()")).lowerBound
        XCTAssertLessThan(
            appSource.distance(from: appSource.startIndex, to: isLoadedOffset),
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

    private func sourceFileContents(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: projectRootURL.appending(path: relativePath), encoding: .utf8)
    }
}
