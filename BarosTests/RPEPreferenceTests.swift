import XCTest
@testable import Baros

final class RPEPreferenceTests: XCTestCase {
    func testAutomaticFollowsRestoredDataAndExplicitChoiceWins() {
        XCTAssertFalse(RPEPreferencePolicy.isEnabled(selection: "automatic", hasLoggedRPE: false))
        XCTAssertTrue(RPEPreferencePolicy.isEnabled(selection: "automatic", hasLoggedRPE: true))
        XCTAssertFalse(RPEPreferencePolicy.isEnabled(selection: "off", hasLoggedRPE: true))
        XCTAssertTrue(RPEPreferencePolicy.isEnabled(selection: "on", hasLoggedRPE: false))
    }

    @MainActor
    func testAutomaticExcludesOtherOwnersAndDeletedData() {
        let set = LoggedSet(orderIndex: 0, rpe: 8)
        let exercise = LoggedExercise(orderIndex: 0, sets: [set])
        let session = WorkoutSession(title: "Test", startedAt: .now, status: .completed, source: .blank, loggedExercises: [exercise])
        set.loggedExercise = exercise
        exercise.session = session
        XCTAssertTrue(RPEPreferencePolicy.isVisibleRatedSet(set, ownerTokenIdentifier: nil))
        session.syncOwnerTokenIdentifier = "someone-else"
        XCTAssertFalse(RPEPreferencePolicy.isVisibleRatedSet(set, ownerTokenIdentifier: nil))
        XCTAssertTrue(RPEPreferencePolicy.isVisibleRatedSet(set, ownerTokenIdentifier: "someone-else"))
        exercise.deletedAt = .now
        XCTAssertFalse(RPEPreferencePolicy.isVisibleRatedSet(set, ownerTokenIdentifier: "someone-else"))
    }
}
