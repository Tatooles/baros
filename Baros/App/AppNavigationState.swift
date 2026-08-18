import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case history
    case home
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history:
            return "History"
        case .home:
            return "Home"
        case .profile:
            return "Profile"
        }
    }

    var symbolName: String {
        switch self {
        case .history:
            return "clock.arrow.circlepath"
        case .home:
            return "house.fill"
        case .profile:
            return "person"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .history:
            return "HistoryTab"
        case .home:
            return "HomeTab"
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

enum ProfileRoute: Hashable {
    case settings
}

@Observable
final class AppNavigationState {
    var selectedTab: AppTab
    var historyMode: HistoryMode
    var historyPath: [HistoryRoute]
    var profilePath: [ProfileRoute]
    private(set) var activeWorkoutID: UUID?
    private(set) var isActiveWorkoutPresented: Bool
    private var hasReconciledActiveWorkout: Bool
    private var suppressesActiveWorkoutAccessory: Bool

    var showsActiveWorkoutAccessory: Bool {
        activeWorkoutID != nil && !isActiveWorkoutPresented && !suppressesActiveWorkoutAccessory
    }

    init(
        selectedTab: AppTab = .home,
        historyMode: HistoryMode = .workouts,
        historyPath: [HistoryRoute] = [],
        profilePath: [ProfileRoute] = []
    ) {
        self.selectedTab = selectedTab
        self.historyMode = historyMode
        self.historyPath = historyPath
        self.profilePath = profilePath
        activeWorkoutID = nil
        isActiveWorkoutPresented = false
        hasReconciledActiveWorkout = false
        suppressesActiveWorkoutAccessory = false
    }

    func reconcileActiveWorkout(sessionID: UUID?) {
        guard hasReconciledActiveWorkout else {
            hasReconciledActiveWorkout = true
            activeWorkoutID = sessionID
            selectedTab = .home
            isActiveWorkoutPresented = sessionID != nil
            suppressesActiveWorkoutAccessory = false
            return
        }

        let previousSessionID = activeWorkoutID
        guard previousSessionID != sessionID else { return }

        activeWorkoutID = sessionID

        switch (previousSessionID, sessionID) {
        case (nil, .some):
            selectedTab = .home
            isActiveWorkoutPresented = true
            suppressesActiveWorkoutAccessory = false
        case (.some, nil):
            selectedTab = .home
            isActiveWorkoutPresented = false
            suppressesActiveWorkoutAccessory = false
        case (.some, .some):
            selectedTab = .home
            isActiveWorkoutPresented = false
            suppressesActiveWorkoutAccessory = true
        case (nil, nil):
            break
        }
    }

    func presentActiveWorkout() {
        guard activeWorkoutID != nil else { return }
        suppressesActiveWorkoutAccessory = false
        isActiveWorkoutPresented = true
    }

    func minimizeActiveWorkout() {
        guard activeWorkoutID != nil else { return }
        isActiveWorkoutPresented = false
    }

    func openExerciseHistory(_ route: ExerciseHistoryRoute) {
        selectedTab = .history
        historyMode = .exercises
        historyPath = [.exercise(route)]
    }

    func openSyncSettings() {
        selectedTab = .profile
        profilePath = [.settings]
    }
}
