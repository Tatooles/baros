import Foundation
import XCTest
@testable import Baros

final class SyncDiagnosticsSnapshotTests: XCTestCase {
    func testSummaryIncludesSchedulerFailureAndOutboxErrors() {
        let snapshot = SyncDiagnosticsSnapshot.make(
            ownerTokenIdentifier: "issuer|owner",
            isSyncing: false,
            lastFailureMessage: "Cloud sync could not finish.",
            entries: [
                SyncDiagnosticsEntry(
                    entityKind: "loggedSet",
                    operation: "create",
                    status: "failed",
                    ownerTokenIdentifier: "issuer|owner",
                    attemptCount: 2,
                    updatedAt: Date(timeIntervalSince1970: 1_000),
                    lastErrorMessage: "Server rejected logged set"
                ),
                SyncDiagnosticsEntry(
                    entityKind: "exercise",
                    operation: "update",
                    status: "pending",
                    ownerTokenIdentifier: "issuer|owner",
                    attemptCount: 0,
                    updatedAt: Date(timeIntervalSince1970: 900),
                    lastErrorMessage: nil
                ),
            ]
        )

        XCTAssertTrue(snapshot.summary.contains("owner: issuer|owner"))
        XCTAssertTrue(snapshot.summary.contains("isSyncing: false"))
        XCTAssertTrue(snapshot.summary.contains("lastFailure: Cloud sync could not finish."))
        XCTAssertTrue(snapshot.summary.contains("failed: 1"))
        XCTAssertTrue(snapshot.summary.contains("pending: 1"))
        XCTAssertTrue(snapshot.summary.contains("loggedSet create failed attempts=2"))
        XCTAssertTrue(snapshot.summary.contains("Server rejected logged set"))
    }

    func testSummaryReportsNoActiveOutboxEntries() {
        let snapshot = SyncDiagnosticsSnapshot.make(
            ownerTokenIdentifier: nil,
            isSyncing: false,
            lastFailureMessage: nil,
            entries: []
        )

        XCTAssertTrue(snapshot.summary.contains("owner: nil"))
        XCTAssertTrue(snapshot.summary.contains("activeOutbox: none"))
    }
}
