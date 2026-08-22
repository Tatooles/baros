import XCTest
@testable import Baros

@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testPermanentTabsAreHistoryHomeProfileAndDefaultToHome() {
        let navigationState = AppNavigationState()

        XCTAssertEqual(AppTab.allCases, [.history, .home, .profile])
        XCTAssertEqual(navigationState.selectedTab, .home)
    }

    func testLaunchWithoutActiveWorkoutShowsHomeWithoutPresentationOrAccessory() {
        let navigationState = AppNavigationState(selectedTab: .profile)

        navigationState.reconcileActiveWorkout(sessionID: nil)

        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.mountsActiveWorkoutAccessory)
    }

    func testLaunchWithActiveWorkoutPresentsItOverHomeAndKeepsAccessoryMounted() {
        let navigationState = AppNavigationState(selectedTab: .profile)
        let sessionID = UUID()

        navigationState.reconcileActiveWorkout(sessionID: sessionID)

        XCTAssertEqual(navigationState.activeWorkoutID, sessionID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
        XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
        XCTAssertFalse(navigationState.showsActiveWorkoutReturnAction)
    }

    func testStartingBlankOrPastWorkoutPresentsItOverHome() {
        for sessionID in [UUID(), UUID()] {
            let navigationState = AppNavigationState()
            navigationState.reconcileActiveWorkout(sessionID: nil)

            navigationState.reconcileActiveWorkout(sessionID: sessionID)

            XCTAssertEqual(navigationState.activeWorkoutID, sessionID)
            XCTAssertEqual(navigationState.selectedTab, .home)
            XCTAssertTrue(navigationState.isActiveWorkoutPresented)
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

    func testOpeningAndMinimizingAccessoryPreservesHistoryOrProfileSelectionAndPaths() {
        let exerciseRoute = ExerciseHistoryRoute(exerciseID: UUID(), name: "Bench Press")
        let workoutID = UUID()

        for selectedTab in [AppTab.history, .profile] {
            let navigationState = AppNavigationState()
            navigationState.reconcileActiveWorkout(sessionID: UUID())
            navigationState.minimizeActiveWorkout()
            navigationState.selectedTab = selectedTab
            navigationState.historyPath = [.workout(workoutID), .exercise(exerciseRoute)]
            navigationState.profilePath = [.exerciseLibrary]

            navigationState.presentActiveWorkout()

            XCTAssertEqual(navigationState.selectedTab, selectedTab)
            XCTAssertTrue(navigationState.isActiveWorkoutPresented)
            XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
            XCTAssertEqual(navigationState.historyPath, [.workout(workoutID), .exercise(exerciseRoute)])
            XCTAssertEqual(navigationState.profilePath, [.exerciseLibrary])

            navigationState.minimizeActiveWorkout()

            XCTAssertEqual(navigationState.selectedTab, selectedTab)
            XCTAssertTrue(navigationState.mountsActiveWorkoutAccessory)
            XCTAssertEqual(navigationState.historyPath, [.workout(workoutID), .exercise(exerciseRoute)])
            XCTAssertEqual(navigationState.profilePath, [.exerciseLibrary])
        }
    }

    func testFinishOrDiscardDismissesWorkoutAndReturnsHome() {
        for _ in 0..<2 {
            let navigationState = AppNavigationState()
            navigationState.reconcileActiveWorkout(sessionID: UUID())
            navigationState.minimizeActiveWorkout()
            navigationState.selectedTab = .profile

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
        navigationState.selectedTab = .profile

        navigationState.openWorkoutLiveActivity(
            workoutID: workoutID,
            visibleActiveWorkoutID: workoutID
        )

        XCTAssertEqual(navigationState.selectedTab, .profile)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
    }

    func testLiveActivityReturnOnColdLaunchPresentsMatchingWorkoutOverHome() {
        let workoutID = UUID()
        let navigationState = AppNavigationState(selectedTab: .profile)

        navigationState.openWorkoutLiveActivity(
            workoutID: workoutID,
            visibleActiveWorkoutID: workoutID
        )

        XCTAssertEqual(navigationState.activeWorkoutID, workoutID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
    }

    func testLiveActivityReturnFallsBackHomeForStaleOrOwnerInvisibleWorkout() {
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
        navigationState.selectedTab = .profile

        navigationState.returnHomeFromUnopenableWorkoutLiveActivityLink()

        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
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

    func testOpenSyncSettingsSelectsProfileAndPushesSettingsRoute() {
        let navigationState = AppNavigationState()

        navigationState.openSyncSettings()

        XCTAssertEqual(navigationState.selectedTab, .profile)
        XCTAssertEqual(navigationState.profilePath, [.settings])
    }
}
