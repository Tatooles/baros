import SwiftData
import XCTest
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

    func testBackgroundExpiryDoesNotReplayAndClearsDeliveredAlertOnReturn() {
        // Expiry noticed on return, or by the resumed expiry task first.
        for taskFiresFirst in [false, true] {
            let h = Harness()
            h.timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
            h.timer.setScenePhase(.background)
            h.now = h.now.addingTimeInterval(95)
            if taskFiresFirst { h.timer.expireIfNeeded() }
            XCTAssertEqual(h.notifications.removals, 0)
            h.timer.setScenePhase(.foreground)
            XCTAssertEqual(h.alerts, 0)
            XCTAssertEqual(h.notifications.removals, 1)
            XCTAssertNil(h.timer.current)
            XCTAssertNil(h.persisted)
            h.timer.setScenePhase(.background)
            h.timer.setScenePhase(.foreground)
            XCTAssertEqual(h.notifications.removals, 1)
        }
    }

    func testReturningBeforeExpiryKeepsPendingAlert() {
        let h = Harness()
        h.timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
        h.timer.setScenePhase(.background)
        h.now = h.now.addingTimeInterval(30)
        h.timer.setScenePhase(.foreground)
        XCTAssertEqual(h.notifications.removals, 0)
        XCTAssertEqual(h.timer.current?.isFinished, false)
        h.now = h.now.addingTimeInterval(60)
        h.timer.expireIfNeeded()
        XCTAssertEqual(h.alerts, 1)
        XCTAssertEqual(h.notifications.removals, 1)
    }

    func testOnlyPresentedAndShownSlotsStayRetained() throws {
        let h = Harness()
        let shown = UUID()
        let shownSlot = h.timer.slot(for: shown)
        weak var released: RestTimerSlot?
        do {
            let transient = h.timer.slot(for: UUID())
            released = transient
        }
        XCTAssertNil(released)
        // Rest on a set no view currently shows, e.g. while minimized.
        let unshown = UUID()
        h.timer.start(sessionID: UUID(), setID: unshown, duration: 90)
        let period = try XCTUnwrap(h.timer.current)
        XCTAssertTrue(h.timer.slot(for: unshown).period === period)
        XCTAssertEqual(h.timer.liveSlotCount, 2)
        XCTAssertTrue(h.timer.slot(for: shown) === shownSlot)
        h.timer.cancel()
        XCTAssertNil(h.timer.slot(for: unshown).period)
        h.timer.start(sessionID: UUID(), setID: shown, duration: 90)
        XCTAssertTrue(shownSlot.period === h.timer.current)
        XCTAssertEqual(h.timer.liveSlotCount, 1)
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

    func testOpenedControlsCloseThemselvesUnlessKeptOpen() {
        for keepsOpened in [false, true] {
            let timer = RestTimerCoordinator(keepsOpenedControls: keepsOpened)
            timer.start(sessionID: UUID(), setID: UUID(), duration: 90)
            // Controls that open on their own at the start of rest always close themselves.
            XCTAssertTrue(timer.isCollapseScheduled)
            timer.collapseControls()
            timer.toggleControls()
            XCTAssertEqual(timer.current?.controlsExpanded, true)
            XCTAssertEqual(timer.isCollapseScheduled, !keepsOpened)
            timer.adjust(by: 15)
            XCTAssertEqual(timer.isCollapseScheduled, !keepsOpened)
            timer.cancel()
        }
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

    func testOwnedRestWaitsForInitialOwnerResolutionAndCancelsAfterConfirmedSignOut() throws {
        let h = Harness()
        let (context, engine, session, exercise) = try fixture(timer: h.timer)
        session.syncOwnerTokenIdentifier = "owner-a"
        try engine.toggleSetCompletion(exercise.sortedSets[0], context: context)
        let rest = try XCTUnwrap(h.persisted)
        let restored = RestTimerCoordinator(
            restoredRest: rest, clock: { h.now }, notifications: h.notifications,
            schedulesTasks: false)
        restored.reconcile(with: nil, ownerState: .resolving(ownerTokenIdentifier: nil))
        XCTAssertEqual(restored.restForReconciliation, rest)
        XCTAssertEqual(h.notifications.removals, 0)
        let unrelated = WorkoutSession(title: "Unclaimed", startedAt: h.now, status: .active, source: .blank)
        restored.reconcile(with: unrelated, ownerState: .resolving(ownerTokenIdentifier: nil))
        XCTAssertEqual(restored.restForReconciliation, rest)
        XCTAssertEqual(h.notifications.removals, 0)
        restored.reconcile(with: session, ownerState: .active(ownerTokenIdentifier: "owner-a"))
        XCTAssertEqual(restored.current?.rest, rest)
        restored.reconcile(with: nil, ownerState: .localOnly)
        XCTAssertNil(restored.restForReconciliation)
        XCTAssertEqual(h.notifications.removals, 1)
    }

    func testCompletionUsesCurrentOwnerSettingsForVisibleUnclaimedWorkout() throws {
        let h = Harness()
        let (context, engine, _, exercise) = try fixture(timer: h.timer)
        let settings = UserSettings(defaultRestTimerSeconds: 120, syncOwnerTokenIdentifier: "owner-a")
        context.insert(settings)
        engine.restSettingsOwnerTokenIdentifier = "owner-a"
        try engine.toggleSetCompletion(exercise.sortedSets[0], context: context)
        XCTAssertEqual(h.timer.current?.rest.remainingSeconds(at: h.now), 120)
    }

    func testDisabledCheckmarkAndRPECompletionSaveWithoutRestOrPermission() throws {
        let h = Harness()
        let (context, engine, session, exercise) = try fixture(timer: h.timer)
        context.insert(UserSettings(defaultRestTimerSeconds: 150))
        let first = exercise.sortedSets[0]
        let second = try engine.addSet(to: exercise, context: context)
        let third = try engine.addSet(to: exercise, context: context)
        h.timer.setEnabled(false)
        try engine.toggleSetCompletion(first, context: context)
        try engine.applyActiveSetRPESelection(
            second, rpe: 8, preparedValues: .init(weight: 100, reps: 5), context: context)
        XCTAssertTrue(first.isCompleted)
        XCTAssertTrue(second.isCompleted)
        XCTAssertEqual(second.rpe, 8)
        enum SaveFailure: Error { case expected }
        XCTAssertThrowsError(
            try engine.toggleSetCompletion(third, context: context, save: { _ in throw SaveFailure.expected }))
        try engine.retrySetSave(in: session, context: context)
        XCTAssertTrue(third.isCompleted)
        XCTAssertNil(h.timer.current)
        XCTAssertNil(h.timer.restForReconciliation)
        XCTAssertNil(h.persisted)
        XCTAssertTrue(h.notifications.scheduled.isEmpty)
        XCTAssertTrue(h.notifications.authorizationRequests.isEmpty)
        XCTAssertEqual(h.alerts, 0)

        // Re-enabling never starts rest for a set that is already complete.
        h.timer.setEnabled(true)
        XCTAssertNil(h.timer.current)
        let fourth = try engine.addSet(to: exercise, context: context)
        try engine.toggleSetCompletion(fourth, context: context)
        XCTAssertEqual(h.timer.current?.rest.setID, fourth.id)
        XCTAssertEqual(h.timer.current?.rest.remainingSeconds(at: h.now), 150)
    }

    func testDisablingDuringRestCancelsPresentationAlertsAndRestorableState() throws {
        let h = Harness()
        let (context, engine, session, exercise) = try fixture(timer: h.timer)
        let set = exercise.sortedSets[0]
        let slot = h.timer.slot(for: set.id)
        try engine.toggleSetCompletion(set, context: context)
        let rest = try XCTUnwrap(h.timer.current?.rest)
        h.timer.reportInlineVisibility(false, restID: rest.id)
        XCTAssertTrue(h.timer.showsHeaderFallback)
        h.timer.setEnabled(false)
        XCTAssertNil(h.timer.current)
        XCTAssertNil(slot.period)
        XCTAssertFalse(h.timer.showsHeaderFallback)
        XCTAssertNil(h.timer.restForReconciliation)
        XCTAssertNil(h.persisted)
        XCTAssertEqual(h.notifications.removals, 1)
        h.now = rest.endsAt.addingTimeInterval(1)
        h.timer.expireIfNeeded()
        h.timer.setScenePhase(.background)
        h.timer.setScenePhase(.foreground)
        XCTAssertEqual(h.alerts, 0)
        let restored = RestTimerCoordinator(
            restoredRest: rest, isEnabled: false, clock: { h.now }, notifications: h.notifications,
            schedulesTasks: false)
        restored.reconcile(with: session, ownerState: .resolving(ownerTokenIdentifier: nil))
        XCTAssertNil(restored.restForReconciliation)
        XCTAssertEqual(h.notifications.scheduled.count, 1)
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
