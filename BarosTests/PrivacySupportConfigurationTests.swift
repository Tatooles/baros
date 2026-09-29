import XCTest
@testable import Baros

final class PrivacySupportConfigurationTests: XCTestCase {
    func testReleaseLinksUseBarosDomain() {
        let configuration = PrivacySupportConfiguration.release

        XCTAssertEqual(configuration.privacyPolicyURL.absoluteString, "https://baros.fit/privacy")
        XCTAssertEqual(configuration.supportURL.absoluteString, "https://baros.fit/support")
    }
}
