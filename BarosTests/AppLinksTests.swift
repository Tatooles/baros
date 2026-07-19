import XCTest
@testable import Baros

final class AppLinksTests: XCTestCase {
    func testGitHubRepositoryURLUsesCanonicalRepository() {
        let url = AppLinks.githubRepositoryURL

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/Tatooles/lifting-log-ios")
        XCTAssertEqual(url.absoluteString, "https://github.com/Tatooles/lifting-log-ios")
    }
}
