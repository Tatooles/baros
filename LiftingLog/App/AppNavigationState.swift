import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case history
    case workout
    case profile

    var id: String { rawValue }

    func title(isWorkoutActive: Bool) -> String {
        switch self {
        case .history:
            return "History"
        case .workout:
            return isWorkoutActive ? "Current" : "Start"
        case .profile:
            return "Profile"
        }
    }

    func symbolName(isWorkoutActive: Bool) -> String {
        switch self {
        case .history:
            return "clock"
        case .workout:
            return isWorkoutActive ? "timer" : "plus.circle"
        case .profile:
            return "person"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .history:
            return "HistoryTab"
        case .workout:
            return "WorkoutTab"
        case .profile:
            return "ProfileTab"
        }
    }
}

enum HistoryMode: String, CaseIterable, Identifiable {
    case workouts
    case exercises

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts:
            return "Workouts"
        case .exercises:
            return "Exercises"
        }
    }
}

enum HistoryRoute: Hashable {
    case exercise(ExerciseHistoryRoute)
}

@Observable
final class AppNavigationState {
    var selectedTab: AppTab
    var historyMode: HistoryMode
    var historyPath: [HistoryRoute]

    init(
        selectedTab: AppTab = .workout,
        historyMode: HistoryMode = .workouts,
        historyPath: [HistoryRoute] = []
    ) {
        self.selectedTab = selectedTab
        self.historyMode = historyMode
        self.historyPath = historyPath
    }

    func openExerciseHistory(_ route: ExerciseHistoryRoute) {
        selectedTab = .history
        historyMode = .exercises
        historyPath = [.exercise(route)]
    }
}
