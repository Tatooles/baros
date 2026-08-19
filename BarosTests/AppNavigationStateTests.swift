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
        XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
    }

    func testLaunchWithActiveWorkoutPresentsItOverHomeWithoutAccessory() {
        let navigationState = AppNavigationState(selectedTab: .profile)
        let sessionID = UUID()

        navigationState.reconcileActiveWorkout(sessionID: sessionID)

        XCTAssertEqual(navigationState.activeWorkoutID, sessionID)
        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertTrue(navigationState.isActiveWorkoutPresented)
        XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
    }

    func testStartingBlankOrPastWorkoutPresentsItOverHome() {
        for sessionID in [UUID(), UUID()] {
            let navigationState = AppNavigationState()
            navigationState.reconcileActiveWorkout(sessionID: nil)

            navigationState.reconcileActiveWorkout(sessionID: sessionID)

            XCTAssertEqual(navigationState.activeWorkoutID, sessionID)
            XCTAssertEqual(navigationState.selectedTab, .home)
            XCTAssertTrue(navigationState.isActiveWorkoutPresented)
            XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
        }
    }

    func testMinimizingActiveWorkoutShowsAccessoryOverHome() {
        let navigationState = AppNavigationState()
        navigationState.reconcileActiveWorkout(sessionID: UUID())

        navigationState.minimizeActiveWorkout()

        XCTAssertEqual(navigationState.selectedTab, .home)
        XCTAssertFalse(navigationState.isActiveWorkoutPresented)
        XCTAssertTrue(navigationState.showsActiveWorkoutAccessory)
        XCTAssertTrue(navigationState.showsActiveWorkoutReturnAction)
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
            XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
            XCTAssertEqual(navigationState.historyPath, [.workout(workoutID), .exercise(exerciseRoute)])
            XCTAssertEqual(navigationState.profilePath, [.exerciseLibrary])

            navigationState.minimizeActiveWorkout()

            XCTAssertEqual(navigationState.selectedTab, selectedTab)
            XCTAssertTrue(navigationState.showsActiveWorkoutAccessory)
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
            XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
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
        XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
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
        XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
        XCTAssertTrue(navigationState.showsActiveWorkoutReturnAction)

        navigationState.presentActiveWorkout()
        navigationState.minimizeActiveWorkout()

        XCTAssertTrue(navigationState.showsActiveWorkoutAccessory)
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
        XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)
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
        XCTAssertFalse(navigationState.showsActiveWorkoutAccessory)

        navigationState.presentActiveWorkout()
        navigationState.minimizeActiveWorkout()

        XCTAssertTrue(navigationState.showsActiveWorkoutAccessory)
    }

    func testOpenExerciseHistorySelectsHistoryExercisesAndStoresRoute() {
        let navigationState = AppNavigationState(selectedTab: .home, historyMode: .workouts)
        let route = ExerciseHistoryRoute(exerciseID: UUID(), name: "Bench Press")

        navigationState.openExerciseHistory(route)

        XCTAssertEqual(navigationState.selectedTab, .history)
        XCTAssertEqual(navigationState.historyMode, .exercises)
        XCTAssertEqual(navigationState.historyPath, [.exercise(route)])
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
