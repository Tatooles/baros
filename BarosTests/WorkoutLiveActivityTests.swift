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

    func testNewSynchronizationInvalidatesInFlightReconciliation() {
        var freshness = WorkoutLiveActivityReconciliationFreshness()
        let workoutReconciliation = freshness.beginSynchronization()

        XCTAssertTrue(freshness.isCurrent(workoutReconciliation))

        let ownerChangeReconciliation = freshness.beginSynchronization()

        XCTAssertFalse(freshness.isCurrent(workoutReconciliation))
        XCTAssertTrue(freshness.isCurrent(ownerChangeReconciliation))
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

        let workoutIDsToClear = WorkoutLiveActivityRequestHistoryPolicy.workoutIDsToClear(
            activeWorkoutID: nil,
            successfullyRequestedWorkoutIDs: store.successfullyRequestedWorkoutIDs,
            activities: [visibleActivity]
        )
        for workoutID in workoutIDsToClear {
            store.clearSuccessfulRequest(workoutID: workoutID)
        }

        let returningOwnerPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [],
            successfullyRequestedWorkoutID: store.hasSuccessfullyRequested(workoutID: workoutID)
                ? workoutID
                : nil,
            suppressedWorkoutID: store.isSuppressed(workoutID: workoutID)
                ? workoutID
                : nil
        )
        XCTAssertTrue(returningOwnerPlan.shouldRequest)
        XCTAssertFalse(returningOwnerPlan.shouldSuppress)
    }

    func testPrivacyRemovalClearsOnlyVisiblePreviousWorkoutHistoryWhenAnotherWorkoutIsVisible() {
        let previousWorkoutID = UUID()
        let visibleWorkoutID = UUID()
        let alreadyMissingWorkoutID = UUID()
        let previousActivity = WorkoutLiveActivityRecord(
            activityID: "previous",
            workoutID: previousWorkoutID,
            state: .active
        )
        let visibleActivity = WorkoutLiveActivityRecord(
            activityID: "visible",
            workoutID: visibleWorkoutID,
            state: .active
        )

        let workoutIDsToClear = WorkoutLiveActivityRequestHistoryPolicy.workoutIDsToClear(
            activeWorkoutID: visibleWorkoutID,
            successfullyRequestedWorkoutIDs: [
                previousWorkoutID,
                visibleWorkoutID,
                alreadyMissingWorkoutID,
            ],
            activities: [previousActivity, visibleActivity]
        )

        XCTAssertEqual(workoutIDsToClear, [previousWorkoutID])
    }

    func testUnobservedDismissalRemainsSuppressedAfterWorkoutCeasesToBeVisibleToCurrentOwner() throws {
        let suiteName = "WorkoutLiveActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkoutLiveActivityStateStore(defaults: defaults)
        let workoutID = UUID()
        store.recordSuccessfulRequest(workoutID: workoutID)

        let workoutIDsToClear = WorkoutLiveActivityRequestHistoryPolicy.workoutIDsToClear(
            activeWorkoutID: nil,
            successfullyRequestedWorkoutIDs: store.successfullyRequestedWorkoutIDs,
            activities: []
        )
        for workoutID in workoutIDsToClear {
            store.clearSuccessfulRequest(workoutID: workoutID)
        }

        let returningOwnerPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [],
            successfullyRequestedWorkoutID: store.hasSuccessfullyRequested(workoutID: workoutID)
                ? workoutID
                : nil,
            suppressedWorkoutID: store.isSuppressed(workoutID: workoutID)
                ? workoutID
                : nil
        )
        XCTAssertFalse(returningOwnerPlan.shouldRequest)
        XCTAssertTrue(returningOwnerPlan.shouldSuppress)
    }

    func testActivityHistoryRemainsKeyedByWorkoutWhenAnotherWorkoutBecomesVisible() throws {
        let suiteName = "WorkoutLiveActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkoutLiveActivityStateStore(defaults: defaults)
        let dismissedWorkoutID = UUID()
        let visibleWorkoutID = UUID()

        store.suppress(workoutID: dismissedWorkoutID)
        store.recordSuccessfulRequest(workoutID: visibleWorkoutID)

        XCTAssertTrue(store.hasSuccessfullyRequested(workoutID: dismissedWorkoutID))
        XCTAssertTrue(store.hasSuccessfullyRequested(workoutID: visibleWorkoutID))
        XCTAssertTrue(store.isSuppressed(workoutID: dismissedWorkoutID))
        XCTAssertFalse(store.isSuppressed(workoutID: visibleWorkoutID))

        let returningOwnerPlan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: dismissedWorkoutID,
            activities: [],
            successfullyRequestedWorkoutID: dismissedWorkoutID,
            suppressedWorkoutID: dismissedWorkoutID
        )
        XCTAssertFalse(returningOwnerPlan.shouldRequest)
    }

    func testActivityHistoryPreservesLegacySingleWorkoutIdentifiers() throws {
        let suiteName = "WorkoutLiveActivityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyWorkoutID = UUID()
        let newWorkoutID = UUID()
        defaults.set(
            legacyWorkoutID.uuidString,
            forKey: "workoutLiveActivity.successfullyRequestedWorkoutID"
        )
        defaults.set(
            legacyWorkoutID.uuidString,
            forKey: "workoutLiveActivity.suppressedWorkoutID"
        )
        let store = WorkoutLiveActivityStateStore(defaults: defaults)

        store.recordSuccessfulRequest(workoutID: newWorkoutID)

        XCTAssertTrue(store.hasSuccessfullyRequested(workoutID: legacyWorkoutID))
        XCTAssertTrue(store.hasSuccessfullyRequested(workoutID: newWorkoutID))
        XCTAssertTrue(store.isSuppressed(workoutID: legacyWorkoutID))
        XCTAssertFalse(store.isSuppressed(workoutID: newWorkoutID))
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
