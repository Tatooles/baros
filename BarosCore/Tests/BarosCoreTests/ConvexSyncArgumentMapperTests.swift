import XCTest
@testable import BarosCore

final class ConvexSyncArgumentMapperTests: XCTestCase {
    func testAccountDataDeletionResultDecodesConvexResponse() throws {
        let json = """
        {
          "status": "deleted",
          "deletedCounts": {
            "loggedSets": 5,
            "loggedExercises": 4,
            "workoutSessions": 3,
            "exercises": 2,
            "userSettings": 1
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(AccountDataDeletionResult.self, from: data)

        XCTAssertEqual(result.status, "deleted")
        XCTAssertEqual(result.deletedCounts.loggedSets, 5)
        XCTAssertEqual(result.deletedCounts.loggedExercises, 4)
        XCTAssertEqual(result.deletedCounts.workoutSessions, 3)
        XCTAssertEqual(result.deletedCounts.exercises, 2)
        XCTAssertEqual(result.deletedCounts.userSettings, 1)
    }
}
