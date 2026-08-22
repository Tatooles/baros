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
    case workout(UUID)
    case exercise(ExerciseHistoryRoute)
}

enum ProfileRoute: Hashable {
    case settings
    case exerciseLibrary
}

@Observable
final class AppNavigationState {
    var selectedTab: AppTab
    var historyMode: HistoryMode
    var historyPath: [HistoryRoute]
    var profilePath: [ProfileRoute]
    private(set) var activeWorkoutID: UUID?
    private(set) var isActiveWorkoutPresented: Bool
    private(set) var fullyPresentedActiveWorkoutID: UUID?
    private var hasReconciledActiveWorkout: Bool
    private var suppressesActiveWorkoutAccessory: Bool
    private var requestsNextActiveWorkoutPresentation: Bool

    /// The accessory stays mounted while the Active Workout is presented, covered by the
    /// presentation rather than removed, so the tab bar keeps a stable width across present and
    /// minimize. Use `showsActiveWorkoutReturnAction` for "the workout is minimized" instead.
    var mountsActiveWorkoutAccessory: Bool {
        activeWorkoutID != nil && !suppressesActiveWorkoutAccessory
    }

    var showsActiveWorkoutReturnAction: Bool {
        activeWorkoutID != nil && !isActiveWorkoutPresented
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
        fullyPresentedActiveWorkoutID = nil
        hasReconciledActiveWorkout = false
        suppressesActiveWorkoutAccessory = false
        requestsNextActiveWorkoutPresentation = false
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
        fullyPresentedActiveWorkoutID = nil

        switch (previousSessionID, sessionID) {
        case (nil, .some):
            selectedTab = .home
            let shouldPresent = requestsNextActiveWorkoutPresentation || !suppressesActiveWorkoutAccessory
            isActiveWorkoutPresented = shouldPresent
            if shouldPresent {
                suppressesActiveWorkoutAccessory = false
            }
            requestsNextActiveWorkoutPresentation = false
        case (.some, nil):
            selectedTab = .home
            isActiveWorkoutPresented = false
            suppressesActiveWorkoutAccessory = true
        case (.some, .some):
            selectedTab = .home
            isActiveWorkoutPresented = false
            suppressesActiveWorkoutAccessory = true
        case (nil, nil):
            break
        }
    }

    func presentActiveWorkout() {
        guard activeWorkoutID != nil else {
            requestsNextActiveWorkoutPresentation = true
            return
        }
        requestsNextActiveWorkoutPresentation = false
        suppressesActiveWorkoutAccessory = false
        fullyPresentedActiveWorkoutID = nil
        isActiveWorkoutPresented = true
    }

    func activeWorkoutPresentationDidFinish() {
        guard isActiveWorkoutPresented, let activeWorkoutID else { return }
        fullyPresentedActiveWorkoutID = activeWorkoutID
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

    func openWorkoutHistory(_ sessionID: UUID) {
        selectedTab = .history
        historyMode = .workouts
        historyPath = [.workout(sessionID)]
    }

    func openSyncSettings() {
        selectedTab = .profile
        profilePath = [.settings]
    }
}
