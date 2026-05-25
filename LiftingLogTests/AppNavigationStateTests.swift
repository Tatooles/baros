import XCTest
@testable import LiftingLog

@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testOpenExerciseHistorySelectsHistoryExercisesAndStoresRoute() {
        let navigationState = AppNavigationState(selectedTab: .workout, historyMode: .workouts)
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
}
