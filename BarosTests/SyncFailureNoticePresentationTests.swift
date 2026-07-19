import XCTest
@testable import Baros

final class SyncFailureNoticePresentationTests: XCTestCase {
    func testShowsCurrentFailureWhenItHasNotBeenDismissed() {
        let presentation = SyncFailureNoticePresentation()

        XCTAssertTrue(
            presentation.shouldShowNotice(
                showsGlobalFailureNotice: true,
                currentFailureSignature: "failure-a",
                dismissedFailureSignature: nil
            )
        )
    }

    func testHidesCurrentFailureAfterDismissal() {
        let presentation = SyncFailureNoticePresentation()

        XCTAssertFalse(
            presentation.shouldShowNotice(
                showsGlobalFailureNotice: true,
                currentFailureSignature: "failure-a",
                dismissedFailureSignature: "failure-a"
            )
        )
    }

    func testNewFailureSignatureShowsAfterPreviousDismissal() {
        let presentation = SyncFailureNoticePresentation()

        XCTAssertTrue(
            presentation.shouldShowNotice(
                showsGlobalFailureNotice: true,
                currentFailureSignature: "failure-b",
                dismissedFailureSignature: "failure-a"
            )
        )
    }

    func testDismissRecordsCurrentFailureSignature() {
        let presentation = SyncFailureNoticePresentation()

        XCTAssertEqual(
            presentation.dismissedSignature(
                currentFailureSignature: "failure-a",
                dismissedFailureSignature: nil
            ),
            "failure-a"
        )
    }
}
