import XCTest
@testable import LiftingLog

final class AppInitializationOrderTests: XCTestCase {
    func testAppCreatesAndInjectsOneSyncOutboxTransaction() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertEqual(
            appSource.components(separatedBy: "SyncOutboxTransaction(").count - 1,
            1,
            "The app should construct one shared SyncOutboxTransaction."
        )
        XCTAssertTrue(
            appSource.contains("@State private var syncOutboxTransaction: SyncOutboxTransaction")
        )
        XCTAssertTrue(appSource.contains(".environment(syncOutboxTransaction)"))
    }

    func testConvexClientIsInitializedAfterClerkConfiguration() throws {
        let appSource = try sourceFileContents("LiftingLog/App/LiftingLogApp.swift")

        XCTAssertFalse(
            appSource.contains("@State private var convexClient = ConvexClientFactory.makeAuthenticatedClient()"),
            "ConvexClientWithAuth must not be created before LiftingLogApp.init() calls Clerk.configure."
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

    func testUITestHelpersForceSignedOutAuthByDefault() throws {
        let uiTestSource = try sourceFileContents("LiftingLogUITests/LiftingLogUITests.swift")

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
        ]
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
