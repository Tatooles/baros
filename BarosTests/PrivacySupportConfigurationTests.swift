import XCTest
@testable import Baros

final class PrivacySupportConfigurationTests: XCTestCase {
    func testReleaseLinksUseBarosDomain() throws {
        let configuration = PrivacySupportConfiguration.release

        let privacyPolicyURL = try XCTUnwrap(configuration.privacyPolicyURL)
        let supportURL = try XCTUnwrap(configuration.supportURL)

        XCTAssertEqual(privacyPolicyURL.scheme, "https")
        XCTAssertEqual(privacyPolicyURL.host, "baros.fit")
        XCTAssertEqual(privacyPolicyURL.path, "/privacy")
        XCTAssertEqual(privacyPolicyURL.absoluteString, "https://baros.fit/privacy")

        XCTAssertEqual(supportURL.scheme, "https")
        XCTAssertEqual(supportURL.host, "baros.fit")
        XCTAssertEqual(supportURL.path, "/support")
        XCTAssertEqual(supportURL.absoluteString, "https://baros.fit/support")
    }

    func testUnavailableLinksRemainAvailableForPlaceholderStates() {
        let configuration = PrivacySupportConfiguration.issue13Development

        XCTAssertNil(configuration.privacyPolicyURL)
        XCTAssertNil(configuration.supportURL)
        XCTAssertEqual(configuration.unavailableDetailText, "Available before release")
    }
}
