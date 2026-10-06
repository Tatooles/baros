import XCTest
@testable import Baros

@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testPermanentTabsAreHistoryHomeSettingsAndDefaultToHome() {
        let navigationState = AppNavigationState()

        XCTAssertEqual(AppTab.allCases, [.history, .home, .settings])
        XCTAssertEqual(navigationState.selectedTab, .home)
    }

    func testLaunchWithoutActiveWorkoutShowsHomeWithoutPresentationOrAccessory() {
        let navigationState = AppNavigationState(selectedTab: .settings)

        navigationState.reconcileActiveWorkout(sessionID: nil)

        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)
    }

    func testLaunchWithActiveWorkoutDefersAccessoryUntilPresentationFinishes() {
        let navigationState = AppNavigationState(selectedTab: .settings)
        let sessionID = UUID()

        navigationState.reconcileActiveWorkout(sessionID: sessionID)

        XCTAssertEqual(navigationState.activeWorkoutID, sessionID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)
        XCTAssertFalse(navigationState.showsActiveWorkoutReturnAction)

        navigationState.activeWorkoutPresentationDidFinish()

        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
    }

    func testStartingBlankOrPastWorkoutPresentsItOverHome() {
        for sessionID in [UUID(), UUID()] {
            let navigationState = AppNavigationState()
            navigationState.reconcileActiveWorkout(sessionID: nil)

            navigationState.reconcileActiveWorkout(sessionID: sessionID)

            XCTAssertEqual(navigationState.activeWorkoutID, sessionID)
            XCTAssertEqual(navigationState.selectedTab, .home)
            XCTAssertTrue(navigationState.isActiveWorkoutPresented)
            XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)

            // The start sheet also explicitly requests presentation after creating the session.
            navigationState.presentActiveWorkout()
            XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)

            navigationState.activeWorkoutPresentationDidFinish()
            XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
        }
    }

    func testActiveWorkoutPresentationCompletionTracksTheCoveredWorkout() {
        let navigationState = AppNavigationState()
        let sessionID = UUID()

        navigationState.reconcileActiveWorkout(sessionID: sessionID)

        XCTAssertNil(navigationState.fullyPresentedActiveWorkoutID)

        navigationState.activeWorkoutPresentationDidFinish()

        XCTAssertEqual(navigationState.fullyPresentedActiveWorkoutID, sessionID)

        navigationState.minimizeActiveWorkout()
        navigationState.presentActiveWorkout()

        XCTAssertNil(navigationState.fullyPresentedActiveWorkoutID)
    }

    func testMinimizingActiveWorkoutShowsAccessoryOverHome() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())

        navigationState.minimizeActiveWorkout()

        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
        XCTAssertTrue(navigationState.showsActiveWorkoutReturnAction)
    }

    func testAccessoryStaysMountedAcrossPresentAndMinimizeSoTheTabBarKeepsItsWidth() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())
        navigationState.minimizeActiveWorkout()

        for _ in 0..<2 {
            XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
            navigationState.presentActiveWorkout()
            XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
            navigationState.minimizeActiveWorkout()
        }

        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
    }

    func testOpeningAndMinimizingAccessoryPreservesHistoryOrSettingsSelectionAndPaths() {
        let exerciseRoute = ExerciseHistoryRoute(exerciseID: UUID(), name: "Bench Press")
        let workoutID = UUID()

        for selectedTab in [AppTab.history, .settings] {
            let navigationState = AppNavigationState()
            navigationState.reconcileActiveWorkout(sessionID: UUID())
            navigationState.minimizeActiveWorkout()
            navigationState.selectedTab = selectedTab
            navigationState.historyPath = [.workout(workoutID), .exercise(exerciseRoute)]
            navigationState.settingsPath = [.exerciseLibrary]

            navigationState.presentActiveWorkout()

            XCTAssertEqual(navigationState.selectedTab, selectedTab)
            XCTAssertTrue(navigationState.isActiveWorkoutPresented)
            XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
            XCTAssertEqual(navigationState.historyPath, [.workout(workoutID), .exercise(exerciseRoute)])
            XCTAssertEqual(navigationState.settingsPath, [.exerciseLibrary])

            navigationState.minimizeActiveWorkout()

            XCTAssertEqual(navigationState.selectedTab, selectedTab)
            XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
            XCTAssertEqual(navigationState.historyPath, [.workout(workoutID), .exercise(exerciseRoute)])
            XCTAssertEqual(navigationState.settingsPath, [.exerciseLibrary])
        }
    }

    func testFinishOrDiscardDismissesWorkoutAndReturnsHome() {
        for _ in 0..<2 {
            let navigationState = AppNavigationState()
            navigationState.reconcileActiveWorkout(sessionID: UUID())
            navigationState.minimizeActiveWorkout()
            navigationState.selectedTab = .settings

            navigationState.reconcileActiveWorkout(sessionID: nil)

            XCTAssertNil(navigationState.activeWorkoutID)
            XCTAssertEqual(navigationState.selectedTab, .home)
            XCTAssertFalse(navigationState.isActiveWorkoutPresented)
            XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)
        }
    }

    func testActiveWorkoutDisappearingAfterCurrentOwnerChangeReturnsHome() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())
        navigationState.minimizeActiveWorkout()
        navigationState.selectedTab = .history

        navigationState.reconcileActiveWorkout(sessionID: nil)

        XCTAssertNil(navigationState.activeWorkoutID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)
    }

    func testDelayedReplacementAfterCurrentOwnerChangeStaysDismissedUntilExplicitReturn() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())
        navigationState.selectedTab = .history

        navigationState.reconcileActiveWorkout(sessionID: nil)

        let replacementSessionID = UUID()
        navigationState.reconcileActiveWorkout(sessionID: replacementSessionID)

        XCTAssertEqual(navigationState.activeWorkoutID, replacementSessionID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)
        XCTAssertTrue(navigationState.showsActiveWorkoutReturnAction)

        navigationState.presentActiveWorkout()
        navigationState.minimizeActiveWorkout()

        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
        XCTAssertTrue(navigationState.showsActiveWorkoutReturnAction)
    }

    func testExplicitReturnRequestedBeforeDelayedWorkoutAppearsPresentsIt() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())
        navigationState.reconcileActiveWorkout(sessionID: nil)

        navigationState.presentActiveWorkout()

        let replacementSessionID = UUID()
        navigationState.reconcileActiveWorkout(sessionID: replacementSessionID)

        XCTAssertEqual(navigationState.activeWorkoutID, replacementSessionID)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)

        navigationState.activeWorkoutPresentationDidFinish()

        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
    }

    func testNextWorkoutDoesNotInheritPreviousWorkoutAccessoryReadiness() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())
        navigationState.activeWorkoutPresentationDidFinish()
        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)

        navigationState.reconcileActiveWorkout(sessionID: nil)
        navigationState.presentActiveWorkout()
        navigationState.reconcileActiveWorkout(sessionID: UUID())

        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)

        navigationState.activeWorkoutPresentationDidFinish()

        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
    }

    func testVisibleActiveWorkoutChangingDismissesOldPresentationAndReturnsHome() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())
        navigationState.selectedTab = .history
        let replacementSessionID = UUID()

        navigationState.reconcileActiveWorkout(sessionID: replacementSessionID)

        XCTAssertEqual(navigationState.activeWorkoutID, replacementSessionID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)

        navigationState.presentActiveWorkout()
        navigationState.minimizeActiveWorkout()

        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
    }

    func testLiveActivityReturnPresentsMatchingWorkoutOverCurrentWarmTab() {
        let workoutID = UUID()
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: workoutID)
        navigationState.minimizeActiveWorkout()
        navigationState.selectedTab = .settings

        navigationState.openWorkoutLiveActivity(
            workoutID: workoutID,
            visibleActiveWorkoutID: workoutID
        )

        XCTAssertEqual(navigationState.selectedTab, .settings)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
    }

    func testLiveActivityReturnOnColdLaunchPresentsMatchingWorkoutOverHome() {
        let workoutID = UUID()
        let navigationState = AppNavigationState(selectedTab: .settings)

        navigationState.openWorkoutLiveActivity(
            workoutID: workoutID,
            visibleActiveWorkoutID: workoutID
        )

        XCTAssertEqual(navigationState.activeWorkoutID, workoutID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
    }

    func testLiveActivityReturnFallsBackHomeForStaleWorkoutOrWorkoutNotVisibleToCurrentOwner() {
        let visibleWorkoutID = UUID()
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: visibleWorkoutID)
        navigationState.minimizeActiveWorkout()
        navigationState.selectedTab = .history

        navigationState.openWorkoutLiveActivity(
            workoutID: UUID(),
            visibleActiveWorkoutID: visibleWorkoutID
        )

        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
    }

    func testMalformedLiveActivityReturnFallsBackHome() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())
        navigationState.selectedTab = .settings

        navigationState.returnHomeFromUnopenableWorkoutLiveActivityLink()

        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
    }

    func testOpenExerciseHistorySelectsHistoryExercisesAndStoresRoute() {
        let navigationState = AppNavigationState(selectedTab: .home, historyMode: .workouts)
        let route = ExerciseHistoryRoute(exerciseID: UUID(), name: "Bench Press")

        navigationState.openExerciseHistory(route)

        XCTAssertEqual(navigationState.selectedTab, .history)
        XCTAssertEqual(navigationState.historyMode, .exercises)
        XCTAssertEqual(navigationState.historyPath, [.exercise(route)])
    }

    func testOpenWorkoutHistoryFromHomeSelectsWorkoutHistoryAndStoresRoute() {
        let navigationState = AppNavigationState(selectedTab: .home, historyMode: .exercises)
        let workoutID = UUID()

        navigationState.openWorkoutHistory(workoutID)

        XCTAssertEqual(navigationState.selectedTab, .history)
        XCTAssertEqual(navigationState.historyMode, .workouts)
        XCTAssertEqual(navigationState.historyPath, [.workout(workoutID)])
    }

    func testClearHistoryPathRemovesRoute() {
        let route = ExerciseHistoryRoute(exerciseID: UUID(), name: "Bench Press")
        let navigationState = AppNavigationState(selectedTab: .history, historyMode: .exercises)
        navigationState.openExerciseHistory(route)

        navigationState.historyPath = []

        XCTAssertTrue(navigationState.historyPath.isEmpty)
    }

    func testOpenSyncSettingsSelectsSettingsAtItsRoot() {
        let navigationState = AppNavigationState(settingsPath: [.exerciseLibrary])

        navigationState.openSyncSettings()

        XCTAssertEqual(navigationState.selectedTab, .settings)
        XCTAssertEqual(navigationState.settingsPath, [])
    }
}
