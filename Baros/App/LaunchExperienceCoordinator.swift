import Foundation

struct LaunchExperienceState: Equatable {
    let hasCompletedOnboarding: Bool
    let lastProcessedAppVersion: String?
    let lastSeenWhatsNewVersion: String?
}

enum LaunchExperienceDecision: Equatable {
    case deferUntilOwnerScopeResolves
    case skipForActiveWorkout
    case evaluateStore
}

enum LaunchExperienceCoordinator {
    static func decision(
        currentOwnerState: CurrentOwnerCoordinator.State,
        activeWorkoutID: UUID?
    ) -> LaunchExperienceDecision {
        if case .resolving(ownerTokenIdentifier: nil) = currentOwnerState {
            return .deferUntilOwnerScopeResolves
        }
        if activeWorkoutID != nil {
            return .skipForActiveWorkout
        }
        return .evaluateStore
    }

    /// A signed-in launch without completed onboarding is a returning user on a
    /// reinstall: Clerk's keychain session outlives the app, but the onboarding
    /// flag in UserDefaults does not. Those users skip onboarding entirely.
    static func shouldCompleteOnboardingSilently(
        state: LaunchExperienceState,
        currentOwnerState: CurrentOwnerCoordinator.State
    ) -> Bool {
        guard !state.hasCompletedOnboarding else {
            return false
        }

        switch currentOwnerState {
        case .active, .resolving(ownerTokenIdentifier: .some):
            return true
        case .localOnly, .resolving(ownerTokenIdentifier: nil):
            return false
        }
    }

    static func nextPresentation(
        state: LaunchExperienceState,
        currentRelease: AppReleaseDefinition
    ) -> LaunchExperiencePresentation? {
        guard state.hasCompletedOnboarding else {
            return .onboarding
        }

        guard state.lastProcessedAppVersion != currentRelease.version else {
            return nil
        }

        guard let currentWhatsNew = currentRelease.whatsNew,
              state.lastSeenWhatsNewVersion != currentWhatsNew.version else {
            return nil
        }

        return .whatsNew(currentWhatsNew)
    }
}
