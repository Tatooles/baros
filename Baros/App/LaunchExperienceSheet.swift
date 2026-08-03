import SwiftUI

enum LaunchExperiencePresentation: Identifiable, Equatable {
    case onboarding
    case whatsNew(WhatsNewRelease)

    var id: String {
        switch self {
        case .onboarding:
            "onboarding"
        case .whatsNew(let release):
            "whats-new-\(release.version)"
        }
    }
}

struct LaunchExperienceSheet: View {
    let presentation: LaunchExperiencePresentation
    let primaryAction: () -> Void

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .onboarding:
            OnboardingFlow(onCompleted: primaryAction)
        case .whatsNew(let release):
            WhatsNewSheet(
                sheetID: release.sheetID,
                onDismiss: primaryAction
            )
        }
    }
}
