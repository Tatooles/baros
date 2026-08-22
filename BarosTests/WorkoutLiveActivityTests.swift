import XCTest
@testable import Baros

final class WorkoutLiveActivityTests: XCTestCase {
    func testSnapshotDerivesCommittedTitleStartDateAndVisibleSetProgress() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let completedSet = LoggedSet(orderIndex: 0, isCompleted: true)
        let openSet = LoggedSet(orderIndex: 1)
        let deletedSet = LoggedSet(orderIndex: 2, isCompleted: true)
        deletedSet.markDeleted(now: Date(timeIntervalSince1970: 2_000))
        let exercise = LoggedExercise(
            orderIndex: 0,
            exerciseSnapshotName: "Bench Press"
        )
        exercise.sets = [completedSet, openSet, deletedSet]
        let session = WorkoutSession(
            title: "Push Day",
            startedAt: startedAt,
            status: .active,
            source: .blank
        )
        session.loggedExercises = [exercise]

        let snapshot = WorkoutLiveActivitySnapshot(session: session)

        XCTAssertEqual(snapshot.workoutID, session.id)
        XCTAssertEqual(snapshot.title, "Push Day")
        XCTAssertEqual(snapshot.startedAt, startedAt)
        XCTAssertEqual(snapshot.completedSetCount, 1)
        XCTAssertEqual(snapshot.totalSetCount, 2)
    }

    func testReconciliationWithoutActiveWorkoutEndsEveryActivity() {
        let first = WorkoutLiveActivityRecord(
            activityID: "first",
            workoutID: UUID(),
            state: .active
        )
        let second = WorkoutLiveActivityRecord(
            activityID: "second",
            workoutID: UUID(),
            state: .dismissed
        )

        let plan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: nil,
            activities: [first, second],
            successfullyRequestedWorkoutID: first.workoutID,
            suppressedWorkoutID: nil
        )

        XCTAssertNil(plan.activityIDToKeep)
        XCTAssertEqual(Set(plan.activityIDsToEnd), ["first", "second"])
        XCTAssertFalse(plan.shouldRequest)
        XCTAssertFalse(plan.shouldSuppress)
        XCTAssertTrue(plan.shouldClearStoredState)
    }

    func testReconciliationKeepsOneMatchingActivityAndEndsDuplicatesAndStaleActivities() {
        let workoutID = UUID()
        let matching = WorkoutLiveActivityRecord(
            activityID: "matching",
            workoutID: workoutID,
            state: .active
        )
        let duplicate = WorkoutLiveActivityRecord(
            activityID: "duplicate",
            workoutID: workoutID,
            state: .pending
        )
        let stale = WorkoutLiveActivityRecord(
            activityID: "stale",
            workoutID: UUID(),
            state: .active
        )

        let plan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [matching, duplicate, stale],
            successfullyRequestedWorkoutID: workoutID,
            suppressedWorkoutID: nil
        )

        XCTAssertEqual(plan.activityIDToKeep, "matching")
        XCTAssertEqual(Set(plan.activityIDsToEnd), ["duplicate", "stale"])
        XCTAssertFalse(plan.shouldRequest)
        XCTAssertFalse(plan.shouldSuppress)
        XCTAssertFalse(plan.shouldClearStoredState)
    }

    func testReconciliationRequestsOnlyForAFreshUnsuppressedWorkout() {
        let workoutID = UUID()

        let freshPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [],
            successfullyRequestedWorkoutID: nil,
            suppressedWorkoutID: nil
        )
        let suppressedPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [],
            successfullyRequestedWorkoutID: nil,
            suppressedWorkoutID: workoutID
        )

        XCTAssertTrue(freshPlan.shouldRequest)
        XCTAssertFalse(freshPlan.shouldSuppress)
        XCTAssertFalse(suppressedPlan.shouldRequest)
        XCTAssertFalse(suppressedPlan.shouldSuppress)
    }

    func testReconciliationSuppressesRecreationWhenRequestedActivityDisappearsOrTerminates() {
        let workoutID = UUID()
        let dismissed = WorkoutLiveActivityRecord(
            activityID: "dismissed",
            workoutID: workoutID,
            state: .dismissed
        )

        for activities in [[], [dismissed]] {
            let plan = WorkoutLiveActivityReconciler.plan(
                activeWorkoutID: workoutID,
                activities: activities,
                successfullyRequestedWorkoutID: workoutID,
                suppressedWorkoutID: nil
            )

            XCTAssertNil(plan.activityIDToKeep)
            XCTAssertFalse(plan.shouldRequest)
            XCTAssertTrue(plan.shouldSuppress)
        }
    }
}
