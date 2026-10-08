import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case history
    case home
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history:
            return "History"
        case .home:
            return "Home"
        case .settings:
            return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .history:
            return "clock.arrow.circlepath"
        case .home:
            return "house.fill"
        case .settings:
            return "gearshape"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .history:
            return "HistoryTab"
        case .home:
            return "HomeTab"
        case .settings:
            return "SettingsTab"
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

enum SettingsRoute: Hashable {
    case exerciseLibrary
    case deleteData(DeleteDataMode)
    #if DEBUG
    case developerDiagnostics
    #endif
}

@Observable
final class AppNavigationState {
    var selectedTab: AppTab
    var historyMode: HistoryMode
    var historyPath: [HistoryRoute]
    var settingsPath: [SettingsRoute]
    private(set) var activeWorkoutID: UUID?
    private(set) var isActiveWorkoutPresented: Bool
    private(set) var fullyPresentedActiveWorkoutID: UUID?
    private var hasReconciledActiveWorkout: Bool
    private var suppressesActiveWorkoutAccessory: Bool
    private var isActiveWorkoutAccessoryReady: Bool
    private var requestsNextActiveWorkoutPresentation: Bool

    /// Mount the accessory only after the first presentation covers the tab bar (or the workout
    /// is minimized early). Then keep it mounted across reopen/minimize to preserve tab bar width.
    /// Use `showsActiveWorkoutReturnAction` for "the workout is minimized" instead.
    var mountsActiveWorkoutAccessory: Bool {
        activeWorkoutID != nil && !suppressesActiveWorkoutAccessory && isActiveWorkoutAccessoryReady
    }

    var showsActiveWorkoutReturnAction: Bool {
        activeWorkoutID != nil && !isActiveWorkoutPresented
    }

    init(
        selectedTab: AppTab = .home,
        historyMode: HistoryMode = .workouts,
        historyPath: [HistoryRoute] = [],
        settingsPath: [SettingsRoute] = []
    ) {
        self.selectedTab = selectedTab
        self.historyMode = historyMode
        self.historyPath = historyPath
        self.settingsPath = settingsPath
        activeWorkoutID = nil
        isActiveWorkoutPresented = false
        fullyPresentedActiveWorkoutID = nil
        hasReconciledActiveWorkout = false
        suppressesActiveWorkoutAccessory = false
        isActiveWorkoutAccessoryReady = false
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
        isActiveWorkoutAccessoryReady = false

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
        isActiveWorkoutAccessoryReady = true
    }

    func minimizeActiveWorkout() {
        guard activeWorkoutID != nil else { return }
        isActiveWorkoutAccessoryReady = true
        isActiveWorkoutPresented = false
    }

    func openWorkoutLiveActivity(
        workoutID: UUID,
        visibleActiveWorkoutID: UUID?
    ) {
        guard workoutID == visibleActiveWorkoutID else {
            returnHomeFromUnopenableWorkoutLiveActivityLink()
            return
        }

        if activeWorkoutID != visibleActiveWorkoutID {
            reconcileActiveWorkout(sessionID: visibleActiveWorkoutID)
        }
        presentActiveWorkout()
    }

    func returnHomeFromUnopenableWorkoutLiveActivityLink() {
        selectedTab = .home
        isActiveWorkoutAccessoryReady = activeWorkoutID != nil
        isActiveWorkoutPresented = false
        fullyPresentedActiveWorkoutID = nil
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
        selectedTab = .settings
        settingsPath = []
    }
}
