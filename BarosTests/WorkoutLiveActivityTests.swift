@preconcurrency import ActivityKit
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

    func testLiveActivityLinkRoundTripsStableWorkoutIdentifier() {
        let workoutID = UUID()
        let url = WorkoutLiveActivityLink.url(for: workoutID)

        XCTAssertEqual(url.scheme, "baros")
        XCTAssertEqual(url.host, "active-workout")
        XCTAssertEqual(WorkoutLiveActivityLink.route(from: url), .workout(workoutID))
    }

    func testLiveActivityLinkDistinguishesMalformedWorkoutRouteFromUnrelatedURL() throws {
        let malformedURL = try XCTUnwrap(
            URL(string: "baros://active-workout/not-a-uuid")
        )
        let unrelatedURL = try XCTUnwrap(
            URL(string: "baros://settings")
        )

        XCTAssertEqual(
            WorkoutLiveActivityLink.route(from: malformedURL),
            .malformedWorkoutLink
        )
        XCTAssertEqual(
            WorkoutLiveActivityLink.route(from: unrelatedURL),
            .unrelated
        )
    }

    func testMalformedWorkoutLinkWaitsForInitialCurrentOwnerResolution() {
        XCTAssertNotNil(
            WorkoutLiveActivityPendingLink(route: .malformedWorkoutLink)
        )

        XCTAssertTrue(
            WorkoutLiveActivityOwnerResolutionPolicy.shouldDeferOwnerSensitiveWork(
                currentOwnerState: .resolving(ownerTokenIdentifier: nil)
            )
        )
        XCTAssertFalse(
            WorkoutLiveActivityOwnerResolutionPolicy.shouldDeferOwnerSensitiveWork(
                currentOwnerState: .resolving(ownerTokenIdentifier: "issuer|owner")
            )
        )
        XCTAssertFalse(
            WorkoutLiveActivityOwnerResolutionPolicy.shouldDeferOwnerSensitiveWork(
                currentOwnerState: .localOnly
            )
        )
        XCTAssertFalse(
            WorkoutLiveActivityOwnerResolutionPolicy.shouldDeferOwnerSensitiveWork(
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner")
            )
        )
    }

    func testSynchronizationDefersNilSnapshotWhileCurrentOwnerIsResolvingWithoutAValidatedOwner() {
        let snapshot = WorkoutLiveActivitySnapshot(
            session: WorkoutSession(
                title: "Workout",
                startedAt: Date(timeIntervalSince1970: 1_000),
                status: .active,
                source: .blank
            )
        )

        XCTAssertFalse(
            WorkoutLiveActivitySynchronizationPolicy.shouldSynchronize(
                snapshot: nil,
                currentOwnerState: .resolving(ownerTokenIdentifier: nil)
            )
        )
        XCTAssertTrue(
            WorkoutLiveActivitySynchronizationPolicy.shouldSynchronize(
                snapshot: snapshot,
                currentOwnerState: .resolving(ownerTokenIdentifier: nil)
            )
        )
        XCTAssertTrue(
            WorkoutLiveActivitySynchronizationPolicy.shouldSynchronize(
                snapshot: nil,
                currentOwnerState: .localOnly
            )
        )
        XCTAssertTrue(
            WorkoutLiveActivitySynchronizationPolicy.shouldSynchronize(
                snapshot: nil,
                currentOwnerState: .active(ownerTokenIdentifier: "issuer|owner")
            )
        )
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
    }

    func testReconciliationPrefersAnActiveActivityOverAPendingDuplicate() {
        let workoutID = UUID()
        let pending = WorkoutLiveActivityRecord(
            activityID: "pending",
            workoutID: workoutID,
            state: .pending
        )
        let active = WorkoutLiveActivityRecord(
            activityID: "active",
            workoutID: workoutID,
            state: .active
        )

        let plan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [pending, active],
            successfullyRequestedWorkoutID: workoutID,
            suppressedWorkoutID: nil
        )

        XCTAssertEqual(plan.activityIDToKeep, "active")
        XCTAssertEqual(plan.activityIDsToEnd, ["pending"])
        XCTAssertFalse(plan.shouldRequest)
        XCTAssertFalse(plan.shouldSuppress)
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

    func testWorkoutCanRequestActivityAgainAfterCeasingToBeVisibleToCurrentOwner() throws {
        let suiteName = "WorkoutLiveActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkoutLiveActivityStateStore(defaults: defaults)
        let workoutID = UUID()
        store.recordSuccessfulRequest(workoutID: workoutID)
        let visibleActivity = WorkoutLiveActivityRecord(
            activityID: "visible",
            workoutID: workoutID,
            state: .active
        )

        if WorkoutLiveActivityRequestHistoryPolicy.shouldClearSuccessfulRequest(
            successfullyRequestedWorkoutID: store.successfullyRequestedWorkoutID,
            activities: [visibleActivity]
        ) {
            store.clearSuccessfulRequest()
        }

        let returningOwnerPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [],
            successfullyRequestedWorkoutID: store.successfullyRequestedWorkoutID,
            suppressedWorkoutID: store.suppressedWorkoutID
        )
        XCTAssertTrue(returningOwnerPlan.shouldRequest)
        XCTAssertFalse(returningOwnerPlan.shouldSuppress)
    }

    func testUnobservedDismissalRemainsSuppressedAfterWorkoutCeasesToBeVisibleToCurrentOwner() throws {
        let suiteName = "WorkoutLiveActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkoutLiveActivityStateStore(defaults: defaults)
        let workoutID = UUID()
        store.recordSuccessfulRequest(workoutID: workoutID)

        if WorkoutLiveActivityRequestHistoryPolicy.shouldClearSuccessfulRequest(
            successfullyRequestedWorkoutID: store.successfullyRequestedWorkoutID,
            activities: []
        ) {
            store.clearSuccessfulRequest()
        }

        let returningOwnerPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [],
            successfullyRequestedWorkoutID: store.successfullyRequestedWorkoutID,
            suppressedWorkoutID: store.suppressedWorkoutID
        )
        XCTAssertFalse(returningOwnerPlan.shouldRequest)
        XCTAssertTrue(returningOwnerPlan.shouldSuppress)
    }

    func testDismissalSuppressionSurvivesWorkoutCeasingToBeVisibleToCurrentOwnerAndClearsForANewWorkout() throws {
        let suiteName = "WorkoutLiveActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkoutLiveActivityStateStore(defaults: defaults)
        let dismissedWorkoutID = UUID()

        store.suppress(workoutID: dismissedWorkoutID)

        XCTAssertEqual(store.suppressedWorkoutID, dismissedWorkoutID)
        let workoutNotVisibleToCurrentOwnerPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: nil,
            activities: [],
            successfullyRequestedWorkoutID: store.successfullyRequestedWorkoutID,
            suppressedWorkoutID: store.suppressedWorkoutID
        )
        XCTAssertFalse(workoutNotVisibleToCurrentOwnerPlan.shouldRequest)
        XCTAssertEqual(store.suppressedWorkoutID, dismissedWorkoutID)

        store.clearSuccessfulRequest()

        XCTAssertNil(store.successfullyRequestedWorkoutID)
        XCTAssertEqual(store.suppressedWorkoutID, dismissedWorkoutID)
        let returningOwnerPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: dismissedWorkoutID,
            activities: [],
            successfullyRequestedWorkoutID: store.successfullyRequestedWorkoutID,
            suppressedWorkoutID: store.suppressedWorkoutID
        )
        XCTAssertFalse(returningOwnerPlan.shouldRequest)

        store.clearState(forWorkoutsOtherThan: dismissedWorkoutID)
        XCTAssertEqual(store.suppressedWorkoutID, dismissedWorkoutID)

        store.clearState(forWorkoutsOtherThan: UUID())
        XCTAssertNil(store.suppressedWorkoutID)
        XCTAssertNil(store.successfullyRequestedWorkoutID)
    }

    func testRequestFailureAllowsOnlyOneForegroundRetryPerWorkout() {
        let workoutID = UUID()
        var retryState = WorkoutLiveActivityRequestRetryState()
        retryState.prepare(for: workoutID)
        retryState.recordFailure(for: workoutID)

        XCTAssertTrue(retryState.blocksRequest)
        XCTAssertTrue(retryState.beginRetryIfAvailable(for: workoutID))
        XCTAssertFalse(retryState.blocksRequest)

        retryState.recordFailure(for: workoutID)

        XCTAssertTrue(retryState.blocksRequest)
        XCTAssertFalse(retryState.beginRetryIfAvailable(for: workoutID))
        XCTAssertTrue(retryState.blocksRequest)

        retryState.prepare(for: UUID())
        XCTAssertFalse(retryState.blocksRequest)
    }

    func testActivityKitTerminalStatesMapToSuppressedLifecycleStates() {
        XCTAssertEqual(
            WorkoutLiveActivityRecord.State(activityState: .active),
            .active
        )
        XCTAssertEqual(
            WorkoutLiveActivityRecord.State(activityState: .dismissed),
            .dismissed
        )
        XCTAssertEqual(
            WorkoutLiveActivityRecord.State(activityState: .stale),
            .stale
        )
        XCTAssertFalse(
            WorkoutLiveActivityRecord.State(activityState: .dismissed).canRemainVisible
        )
    }
}
