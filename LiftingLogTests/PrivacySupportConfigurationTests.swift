import XCTest
@testable import LiftingLog

final class PrivacySupportConfigurationTests: XCTestCase {
    func testReleaseLinksUseSupportSubdomain() throws {
        let configuration = PrivacySupportConfiguration.release

        let privacyPolicyURL = try XCTUnwrap(configuration.privacyPolicyURL)
        let supportURL = try XCTUnwrap(configuration.supportURL)

        XCTAssertEqual(privacyPolicyURL.scheme, "https")
        XCTAssertEqual(privacyPolicyURL.host, "support.liftinglog.app")
        XCTAssertEqual(privacyPolicyURL.path, "/privacy")
        XCTAssertEqual(privacyPolicyURL.absoluteString, "https://support.liftinglog.app/privacy")

        XCTAssertEqual(supportURL.scheme, "https")
        XCTAssertEqual(supportURL.host, "support.liftinglog.app")
        XCTAssertEqual(supportURL.path, "/")
        XCTAssertEqual(supportURL.absoluteString, "https://support.liftinglog.app/")
    }

    func testUnavailableLinksRemainAvailableForPlaceholderStates() {
        let configuration = PrivacySupportConfiguration.issue13Development

        XCTAssertNil(configuration.privacyPolicyURL)
        XCTAssertNil(configuration.supportURL)
        XCTAssertEqual(configuration.unavailableDetailText, "Available before release")
    }
}
