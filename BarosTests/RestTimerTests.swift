import SwiftData
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class RestTimerTests: XCTestCase {
    private final class Notifications: RestNotificationScheduling {
        var scheduled: [WorkoutRest] = []
        var authorizationRequests: [Bool] = []
        var removals = 0
        func schedule(_ rest: WorkoutRest, requestAuthorization: Bool) {
            scheduled.append(rest)
            authorizationRequests.append(requestAuthorization)
        }
        func remove() { removals += 1 }
    }

    @MainActor
    private final class Harness {
        var now = Date(timeIntervalSince1970: 1000)
        var persisted: WorkoutRest?
        var alerts = 0
        let notifications = Notifications()
        lazy var timer = RestTimerCoordinator(
            clock: { [unowned self] in self.now },
            persist: { [unowned self] in self.persisted = $0 }, notifications: notifications,
            foregroundAlert: { [unowned self] in self.alerts += 1 }, schedulesTasks: false)
    }

    func testExpiryUnderSystemOverlayAlertsInAppOnce() {
        XCTAssertEqual(RestTimerScenePhase(.active), .foreground)
        XCTAssertEqual(RestTimerScenePhase(.background), .background)
        let h = Harness()
        h.timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
        h.timer.setScenePhase(RestTimerScenePhase(.inactive))
        h.now = h.now.addingTimeInterval(90)
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.alerts, 1)
        XCTAssertEqual(h.notifications.removals, 1)
        h.timer.setScenePhase(RestTimerScenePhase(.active))
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.alerts, 1)
        XCTAssertEqual(h.notifications.removals, 1)
    }

    func testExpiryDuringFirstAuthorizationPromptAlertsOnceAndWithdrawsTheRequest() {
        let h = Harness()
        h.timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
        XCTAssertEqual(h.notifications.authorizationRequests, [true])
        h.timer.setScenePhase(RestTimerScenePhase(.inactive))
        h.now = h.now.addingTimeInterval(91)
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.alerts, 1)
        XCTAssertEqual(h.notifications.removals, 1)
        h.now = h.now.addingTimeInterval(10)
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.alerts, 1)
        XCTAssertEqual(h.notifications.scheduled.count, 1)
        XCTAssertEqual(h.timer.current?.isFinished, true)
        XCTAssertNil(h.persisted)
    }

    func testSyncAppliedUncompletionAndDeletionChangeLifecycleStateAndCancel() throws {
        for deletion in [false, true] {
            let h = Harness()
            let (context, engine, session, exercise) = try fixture(timer: h.timer)
            let set = exercise.sortedSets[0]
            try engine.toggleSetCompletion(set, context: context)
            let before = RestTimerLifecycleState(
                session: session, rest: h.timer.restForReconciliation, ownerState: .localOnly)
            if deletion { set.markDeleted() } else { set.isCompleted = false }
            let after = RestTimerLifecycleState(
                session: session, rest: h.timer.restForReconciliation, ownerState: .localOnly)
            XCTAssertNotEqual(before, after)
            h.timer.reconcile(with: session)
            XCTAssertNil(h.timer.current)
            XCTAssertEqual(h.notifications.removals, 1)
        }
    }

    func testLifecycleStateWithoutRestIgnoresSetChanges() throws {
        let h = Harness()
        let (context, engine, session, exercise) = try fixture(timer: h.timer)
        let before = RestTimerLifecycleState(session: session, rest: nil, ownerState: .localOnly)
        exercise.sortedSets[0].isCompleted = true
        XCTAssertEqual(RestTimerLifecycleState(session: session, rest: nil, ownerState: .localOnly), before)
        XCTAssertNotEqual(
            RestTimerLifecycleState(session: nil, rest: nil, ownerState: .localOnly), before)
        exercise.sortedSets[0].isCompleted = false
        try engine.toggleSetCompletion(exercise.sortedSets[0], context: context)
        let rest = try XCTUnwrap(h.timer.restForReconciliation)
        let other = WorkoutSession(title: "Other", startedAt: h.now, status: .active, source: .blank)
        XCTAssertFalse(
            RestTimerLifecycleState(session: other, rest: rest, ownerState: .localOnly).starterIsEligible)
        XCTAssertTrue(
            RestTimerLifecycleState(session: session, rest: rest, ownerState: .localOnly).starterIsEligible)
    }

    func testLivePersistenceRestoresLocallyAndSkipSurvivesAnotherLaunch() throws {
        let suite = "RestTimerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = Notifications()
        let timer = RestTimerCoordinator.live(defaults: defaults, notifications: notifications)
        let (context, engine, session, exercise) = try fixture(timer: timer)
        try engine.toggleSetCompletion(exercise.sortedSets[0], context: context)
        let original = try XCTUnwrap(timer.current?.rest)
        let restored = RestTimerCoordinator.live(defaults: defaults, notifications: notifications)
        restored.reconcile(with: session)
        XCTAssertEqual(restored.current?.rest, original)
        restored.skip()
        let afterSkip = RestTimerCoordinator.live(defaults: defaults, notifications: notifications)
        afterSkip.reconcile(with: session)
        XCTAssertNil(afterSkip.current)
        timer.cancel()
        XCTAssertNil(defaults.data(forKey: "active-workout-rest-v1"))
    }

    func testLiveEnabledPreferenceDefaultsOnPersistsAndDisabledLaunchDropsSavedRest() throws {
        let suite = "RestTimerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = Notifications()
        let timer = RestTimerCoordinator.live(defaults: defaults, notifications: notifications)
        XCTAssertTrue(timer.isEnabled)
        let (context, engine, session, exercise) = try fixture(timer: timer)
        try engine.toggleSetCompletion(exercise.sortedSets[0], context: context)
        XCTAssertNotNil(defaults.data(forKey: "active-workout-rest-v1"))

        defaults.set(false, forKey: "rest-timers-enabled-v1")
        let disabledLaunch = RestTimerCoordinator.live(defaults: defaults, notifications: notifications)
        XCTAssertFalse(disabledLaunch.isEnabled)
        disabledLaunch.reconcile(with: session)
        XCTAssertNil(disabledLaunch.current)
        XCTAssertNil(defaults.data(forKey: "active-workout-rest-v1"))

        disabledLaunch.setEnabled(true)
        XCTAssertTrue(RestTimerCoordinator.live(defaults: defaults, notifications: notifications).isEnabled)
        disabledLaunch.setEnabled(false)
        XCTAssertFalse(RestTimerCoordinator.live(defaults: defaults, notifications: notifications).isEnabled)
    }

    private func fixture(timer: RestTimerCoordinator) throws -> (
        ModelContext, ActiveWorkoutEngine, WorkoutSession, LoggedExercise
    ) {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let engine = ActiveWorkoutEngine(restTimer: timer)
        let session = try engine.startBlankWorkout(context: context)
        let exercise = Exercise(name: "Bench", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        context.insert(exercise)
        let logged = try engine.addExercises([exercise], to: session, context: context)[0]
        return (context, engine, session, logged)
    }
}
