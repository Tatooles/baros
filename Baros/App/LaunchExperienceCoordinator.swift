import Foundation

struct LaunchExperienceState: Equatable {
    let hasCompletedOnboarding: Bool
    let lastProcessedAppVersion: String?
    let lastSeenWhatsNewVersion: String?
}

enum LaunchExperienceCoordinator {
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
