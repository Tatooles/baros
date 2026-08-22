import XCTest
@testable import Baros

final class AppLinksTests: XCTestCase {
    func testGitHubRepositoryURLUsesCanonicalRepository() {
        let url = AppLinks.githubRepositoryURL

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/Tatooles/baros")
        XCTAssertEqual(url.absoluteString, "https://github.com/Tatooles/baros")
    }
}
