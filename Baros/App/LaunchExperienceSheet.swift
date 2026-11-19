import BarosCore
import SwiftUI

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
