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

    func testSnapshotIncludesOnlyThisSessionsUnfinishedRest() {
        let session = WorkoutSession(title: "Push Day", startedAt: Date(timeIntervalSince1970: 1_000), status: .active, source: .blank)
        let rest = WorkoutRest(
            id: UUID(), sessionID: session.id, setID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endsAt: Date(timeIntervalSince1970: 1_090), wasSkipped: false
        )
        let period = RestTimerPeriod(rest: rest)
        let resting = WorkoutLiveActivitySnapshot(session: session, restPeriod: period)
        XCTAssertEqual(resting.contentState.restStartedAt, rest.startedAt)
        XCTAssertEqual(resting.contentState.restEndsAt, rest.endsAt)

        let otherSession = WorkoutSession(title: "Other", startedAt: Date(timeIntervalSince1970: 1_000), status: .active, source: .blank)
        let other = WorkoutLiveActivitySnapshot(session: otherSession, restPeriod: period)
        XCTAssertNil(other.restStartedAt)
        XCTAssertNil(other.restEndsAt)

        period.isFinished = true
        XCTAssertEqual(
            WorkoutLiveActivitySnapshot(session: session, restPeriod: period),
            WorkoutLiveActivitySnapshot(session: session)
        )
        period.isFinished = false
        period.rest.wasSkipped = true
        XCTAssertNil(WorkoutLiveActivitySnapshot(session: session, restPeriod: period).restEndsAt)
        let idle = WorkoutLiveActivitySnapshot(session: session)
        XCTAssertNil(idle.contentState.restStartedAt)
        XCTAssertNil(idle.contentState.restEndsAt)
    }

    @MainActor
    func testSnapshotChangesOnRestStartAdjustReplaceSkipClearAndDisable() {
        let session = WorkoutSession(title: "Push Day", startedAt: Date(timeIntervalSince1970: 1_000), status: .active, source: .blank)
        let now = Date(timeIntervalSince1970: 1_000)
        let timer = RestTimerCoordinator(clock: { now }, schedulesTasks: false)
        func snapshot() -> WorkoutLiveActivitySnapshot {
            WorkoutLiveActivitySnapshot(session: session, restPeriod: timer.current)
        }
        let idle = snapshot()
        timer.start(sessionID: session.id, setID: UUID(), duration: 90)
        let started = snapshot()
        XCTAssertNotEqual(started, idle)
        XCTAssertEqual(started, snapshot())
        timer.adjust(by: 15)
        XCTAssertNotEqual(started, snapshot())
        XCTAssertEqual(snapshot().restEndsAt, started.restEndsAt?.addingTimeInterval(15))
        timer.adjust(by: -15)
        XCTAssertEqual(started, snapshot())
        timer.start(sessionID: session.id, setID: UUID(), duration: 120)
        XCTAssertNotEqual(started, snapshot())
        timer.skip()
        XCTAssertEqual(idle, snapshot())
        timer.start(sessionID: session.id, setID: UUID(), duration: 90)
        timer.cancel()
        XCTAssertEqual(idle, snapshot())
        timer.start(sessionID: session.id, setID: UUID(), duration: 90)
        timer.setEnabled(false)
        XCTAssertNil(timer.current)
        XCTAssertEqual(idle, snapshot())
        timer.start(sessionID: session.id, setID: UUID(), duration: 90)
        XCTAssertEqual(idle, snapshot())
    }

    @MainActor
    func testActivityContentUsesRestEndAsStaleDateOnlyWhileResting() {
        let session = WorkoutSession(title: "Push Day", startedAt: Date(timeIntervalSince1970: 1_000), status: .active, source: .blank)
        let period = RestTimerPeriod(rest: WorkoutRest(
            id: UUID(), sessionID: session.id, setID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endsAt: Date(timeIntervalSince1970: 1_090), wasSkipped: false
        ))
        let resting = WorkoutLiveActivitySnapshot(session: session, restPeriod: period)
        let content = WorkoutLiveActivityCoordinator.content(for: resting)
        XCTAssertEqual(content.state, resting.contentState)
        XCTAssertEqual(content.staleDate, period.rest.endsAt)
        period.rest.endsAt += 15
        XCTAssertEqual(
            WorkoutLiveActivityCoordinator.content(
                for: WorkoutLiveActivitySnapshot(session: session, restPeriod: period)
            ).staleDate,
            period.rest.endsAt
        )
        period.isFinished = true
        XCTAssertNil(WorkoutLiveActivityCoordinator.content(
            for: WorkoutLiveActivitySnapshot(session: session, restPeriod: period)
        ).staleDate)
        XCTAssertNil(WorkoutLiveActivityCoordinator.content(
            for: WorkoutLiveActivitySnapshot(session: session)
        ).staleDate)
    }

    func testContentStateDecodesPayloadFromBuildsWithoutRestFields() throws {
        let legacy = Data(#"{"title":"Push Day","completedSetCount":2,"totalSetCount":5}"#.utf8)
        let state = try JSONDecoder().decode(WorkoutLiveActivityAttributes.ContentState.self, from: legacy)
        XCTAssertEqual(state.title, "Push Day")
        XCTAssertEqual(state.completedSetCount, 2)
        XCTAssertEqual(state.totalSetCount, 5)
        XCTAssertNil(state.restStartedAt)
        XCTAssertNil(state.restEndsAt)
    }

    func testAccessoryRestStateMapsCountdownAndFinishedWindow() {
        let sessionID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let period = RestTimerPeriod(rest: WorkoutRest(
            id: UUID(), sessionID: sessionID, setID: UUID(),
            startedAt: now, endsAt: now.addingTimeInterval(90), wasSkipped: false
        ))
        func state(at date: Date) -> ActiveWorkoutAccessoryRestState? {
            ActiveWorkoutAccessoryRestState(period: period, sessionID: sessionID, now: date)
        }
        XCTAssertEqual(state(at: now)?.subtitle, "Rest 1:30")
        XCTAssertEqual(state(at: now)?.systemImage, "hourglass")
        XCTAssertEqual(state(at: now.addingTimeInterval(70.1))?.subtitle, "Rest 0:20")
        XCTAssertEqual(state(at: now.addingTimeInterval(91))?.subtitle, "Rest 0:00")
        period.isFinished = true
        XCTAssertEqual(state(at: now)?.subtitle, "Rest over")
        XCTAssertEqual(state(at: now)?.systemImage, "checkmark")
        XCTAssertNil(ActiveWorkoutAccessoryRestState(period: period, sessionID: UUID(), now: now))
        XCTAssertNil(ActiveWorkoutAccessoryRestState(period: nil, sessionID: sessionID, now: now))
        period.rest.wasSkipped = true
        XCTAssertNil(state(at: now))
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

    func testStaleActivityForActiveWorkoutIsKeptNotSuppressed() {
        let workoutID = UUID()
        let stale = WorkoutLiveActivityRecord(
            activityID: "stale",
            workoutID: workoutID,
            state: .stale
        )

        let plan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [stale],
            successfullyRequestedWorkoutID: workoutID,
            suppressedWorkoutID: nil
        )

        XCTAssertEqual(plan.activityIDToKeep, "stale")
        XCTAssertEqual(plan.activityIDsToEnd, [])
        XCTAssertFalse(plan.shouldRequest)
        XCTAssertFalse(plan.shouldSuppress)
    }

    func testReconciliationPrefersActiveOverStaleDuplicate() {
        let workoutID = UUID()
        let plan = WorkoutLiveActivityReconciler.plan(
            activeWorkoutID: workoutID,
            activities: [
                WorkoutLiveActivityRecord(activityID: "stale", workoutID: workoutID, state: .stale),
                WorkoutLiveActivityRecord(activityID: "active", workoutID: workoutID, state: .active),
            ],
            successfullyRequestedWorkoutID: workoutID,
            suppressedWorkoutID: nil
        )

        XCTAssertEqual(plan.activityIDToKeep, "active")
        XCTAssertEqual(plan.activityIDsToEnd, ["stale"])
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
        XCTAssertFalse(
            WorkoutLiveActivityRecord.State(activityState: .ended).canRemainVisible
        )
        // Stale = past the rest-end stale date; the activity can still be updated.
        XCTAssertTrue(
            WorkoutLiveActivityRecord.State(activityState: .stale).canRemainVisible
        )
    }
}
