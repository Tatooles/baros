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

    func testWorkoutLiveActivityURLRoundTripsStableWorkoutIdentifier() throws {
        let workoutID = UUID()

        let url = AppLinks.workoutLiveActivityURL(for: workoutID)

        XCTAssertEqual(url.scheme, "baros")
        XCTAssertEqual(url.host, "active-workout")
        XCTAssertEqual(AppLinks.workoutID(fromLiveActivityURL: url), workoutID)
    }

    func testWorkoutLiveActivityParserRejectsOtherRoutesAndMalformedIdentifiers() throws {
        XCTAssertNil(
            AppLinks.workoutID(
                fromLiveActivityURL: try XCTUnwrap(URL(string: "https://baros.fit/active-workout/\(UUID())"))
            )
        )
        XCTAssertNil(
            AppLinks.workoutID(
                fromLiveActivityURL: try XCTUnwrap(URL(string: "baros://active-workout/not-a-uuid"))
            )
        )
        XCTAssertNil(
            AppLinks.workoutID(
                fromLiveActivityURL: try XCTUnwrap(URL(string: "baros://history/\(UUID())"))
            )
        )
    }
}
