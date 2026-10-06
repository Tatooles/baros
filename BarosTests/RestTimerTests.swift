import SwiftData
import XCTest

@testable import Baros

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

    func testStartReplaceAndIgnoreStaleVisibilityIncludingSameSet() throws {
        let h = Harness()
        let session = UUID()
        let first = UUID()
        let second = UUID()
        let firstSlot = h.timer.slot(for: first)
        let secondSlot = h.timer.slot(for: second)
        h.timer.start(sessionID: session, setID: first, duration: 90)
        let old = try XCTUnwrap(h.timer.current)
        XCTAssertTrue(old.controlsExpanded)
        XCTAssertFalse(h.timer.showsHeaderFallback)
        XCTAssertEqual(old.rest.remainingSeconds(at: h.now), 90)
        h.timer.reportInlineVisibility(false, restID: old.rest.id)
        XCTAssertTrue(h.timer.showsHeaderFallback)
        h.timer.start(sessionID: session, setID: second, duration: 120)
        let replacement = try XCTUnwrap(h.timer.current)
        XCTAssertNil(firstSlot.period)
        XCTAssertTrue(secondSlot.period === replacement)
        XCTAssertFalse(h.timer.showsHeaderFallback)
        h.timer.reportInlineVisibility(false, restID: old.rest.id)
        XCTAssertNil(h.timer.inlineIsVisible)
        h.timer.reportInlineVisibility(true, restID: replacement.rest.id)
        XCTAssertFalse(h.timer.showsHeaderFallback)
        h.timer.start(sessionID: session, setID: second, duration: 120)
        h.timer.reportInlineVisibility(false, restID: replacement.rest.id)
        XCTAssertNil(h.timer.inlineIsVisible)
        XCTAssertEqual(h.notifications.authorizationRequests, [true, true, true])
    }

    func testAdjustFloorSkipAndNoAlert() throws {
        let h = Harness()
        h.timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
        let rest = try XCTUnwrap(h.timer.current?.rest)
        h.timer.adjust(by: 15)
        XCTAssertEqual(h.timer.current?.rest.endsAt, rest.endsAt.addingTimeInterval(15))
        h.now = rest.endsAt.addingTimeInterval(-5)
        h.timer.adjust(by: -300)
        XCTAssertEqual(h.timer.current?.rest.endsAt, h.now.addingTimeInterval(1))
        XCTAssertEqual(h.notifications.scheduled.count, 3)
        XCTAssertEqual(h.notifications.authorizationRequests, [true, false, false])
        h.timer.skip()
        XCTAssertNil(h.timer.current)
        XCTAssertEqual(h.persisted?.wasSkipped, true)
        XCTAssertEqual(h.notifications.removals, 1)
        h.now = h.now.addingTimeInterval(200)
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.alerts, 0)
    }

    func testExpiryOnlyAlertsOnceInForegroundAndClearsPersistedState() throws {
        let h = Harness()
        h.timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
        h.now = h.now.addingTimeInterval(90)
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.timer.current?.isFinished, true)
        XCTAssertNil(h.persisted)
        XCTAssertEqual(h.alerts, 1)
        XCTAssertEqual(h.notifications.removals, 1)
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.alerts, 1)
    }

    func testBackgroundExpiryDoesNotReplayOnForeground() {
        let h = Harness()
        h.timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
        h.timer.setAppActive(false)
        h.now = h.now.addingTimeInterval(95)
        h.timer.setAppActive(true)
        XCTAssertEqual(h.alerts, 0)
        XCTAssertEqual(h.notifications.removals, 0)
        XCTAssertNil(h.timer.current)
    }

    func testVoiceOverDoesNotAutoOpenControls() {
        let timer = RestTimerCoordinator(voiceOverRunning: { true }, schedulesTasks: false)
        timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
        XCTAssertEqual(timer.current?.controlsExpanded, false)
        timer.toggleControls()
        XCTAssertEqual(timer.current?.controlsExpanded, true)
        timer.collapseControls()
        XCTAssertEqual(timer.current?.controlsExpanded, false)
    }

    func testRestoreUnexpiredAndRejectExpiredSkippedOrInvisibleWorkout() throws {
        let h = Harness()
        let (context, engine, session, exercise) = try fixture(timer: h.timer)
        let set = exercise.sortedSets[0]
        try engine.toggleSetCompletion(set, context: context)
        let rest = try XCTUnwrap(h.persisted)
        let restore = RestTimerCoordinator(
            restoredRest: rest, clock: { h.now }, notifications: h.notifications, schedulesTasks: false)
        restore.reconcile(with: session)
        XCTAssertEqual(restore.current?.rest, rest)
        XCTAssertEqual(restore.current?.controlsExpanded, false)
        XCTAssertEqual(h.notifications.authorizationRequests.last, false)
        restore.reconcile(with: nil)
        XCTAssertNil(restore.current)
        XCTAssertEqual(h.notifications.removals, 1)
        var skipped = rest
        skipped.wasSkipped = true
        let skippedRestore = RestTimerCoordinator(restoredRest: skipped, clock: { h.now }, schedulesTasks: false)
        skippedRestore.reconcile(with: session)
        XCTAssertNil(skippedRestore.current)
        h.now = rest.endsAt.addingTimeInterval(1)
        let expired = RestTimerCoordinator(
            restoredRest: rest, clock: { h.now },
            foregroundAlert: { XCTFail("Expired rest must not replay") }, schedulesTasks: false)
        expired.reconcile(with: session)
        XCTAssertNil(expired.current)
    }

    func testCompletionRPEEditingUncompleteDeleteAndSaveFailureIntegration() throws {
        let h = Harness()
        let (context, engine, session, exercise) = try fixture(timer: h.timer)
        let first = exercise.sortedSets[0]
        let second = try engine.addSet(to: exercise, context: context)
        try engine.toggleSetCompletion(first, context: context)
        let firstRest = try XCTUnwrap(h.timer.current?.rest)
        XCTAssertEqual(firstRest.sessionID, session.id)
        try engine.commitActiveSetDraft(first, values: .init(weight: 100, reps: 6), context: context)
        try engine.applyActiveSetRPESelection(
            first, rpe: 8, preparedValues: .init(weight: 100, reps: 6), context: context)
        XCTAssertEqual(h.timer.current?.rest, firstRest)
        try engine.applyActiveSetRPESelection(
            second, rpe: 9, preparedValues: .init(weight: 100, reps: 5), context: context)
        XCTAssertEqual(h.timer.current?.rest.setID, second.id)
        try engine.toggleSetCompletion(first, context: context)
        XCTAssertEqual(h.timer.current?.rest.setID, second.id)
        try engine.toggleSetCompletion(second, context: context)
        XCTAssertNil(h.timer.current)
        enum SaveFailure: Error { case expected }
        XCTAssertThrowsError(
            try engine.toggleSetCompletion(first, context: context, save: { _ in throw SaveFailure.expected }))
        XCTAssertNil(h.timer.current)
        try engine.retrySetSave(in: session, context: context)
        XCTAssertEqual(h.timer.current?.rest.setID, first.id)
        try engine.removeSet(first, context: context)
        XCTAssertNil(h.timer.current)
        XCTAssertEqual(h.alerts, 0)
    }

    func testFinishDiscardAndRemovingExerciseCancelRest() throws {
        for operation in 0..<3 {
            let h = Harness()
            let (context, engine, session, exercise) = try fixture(timer: h.timer)
            try engine.toggleSetCompletion(exercise.sortedSets[0], context: context)
            switch operation {
            case 0: try engine.finishWorkout(session, context: context)
            case 1: try engine.discardWorkout(session, context: context)
            default: try engine.removeLoggedExercise(exercise, context: context)
            }
            XCTAssertNil(h.timer.current)
            XCTAssertNil(h.persisted)
            XCTAssertEqual(h.notifications.removals, 1)
            XCTAssertEqual(h.alerts, 0)
        }
    }

    func testDurationLookupUsesSettingsWithoutChangingThemWhenAdjusted() throws {
        let h = Harness()
        let (context, engine, _, exercise) = try fixture(timer: h.timer)
        let settings = UserSettings(defaultRestTimerSeconds: 150)
        context.insert(settings)
        try context.save()
        XCTAssertEqual(RestDurationLookup.seconds(for: exercise, settings: settings), 150)
        XCTAssertEqual(RestDurationLookup.seconds(for: exercise, settings: nil), 90)
        try engine.toggleSetCompletion(exercise.sortedSets[0], context: context)
        XCTAssertEqual(h.timer.current?.rest.remainingSeconds(at: h.now), 150)
        h.timer.adjust(by: 15)
        XCTAssertEqual(settings.defaultRestTimerSeconds, 150)
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
        let logged = try engine.addExercise(exercise, to: session, context: context)
        return (context, engine, session, logged)
    }
}
