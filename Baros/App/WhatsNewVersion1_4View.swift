import SwiftUI

/// The release sheet shipped for Baros 1.4, using the same shared page
/// layout and single Continue action as the 1.3 sheet.
struct WhatsNewVersion1_4View: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            LaunchExperiencePage(
                systemImage: "figure.strengthtraining.traditional",
                title: "What's new in Baros 1.4",
                titleIdentifier: "LaunchExperienceTitle"
            ) {
                VStack(alignment: .leading, spacing: 20) {
                    LaunchExperienceFeatureRow(
                        systemImage: "house",
                        title: "Year Ring Home",
                        detail: "Home now shows your training in Month and Year ring views, with Start from pills to repeat a recent workout."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "timer",
                        title: "Rest timers",
                        detail: "Completing a set starts a rest countdown, also shown in the Workout Live Activity and minimized workout bar. Rest timers can be turned off in Settings."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "gearshape",
                        title: "A dedicated Settings tab",
                        detail: "Settings now has its own tab, replacing Profile."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } actions: {
                Button(action: onDismiss) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(AppTheme.brandAccentFill)
                .accessibilityIdentifier("LaunchExperiencePrimaryButton")
            }
        }
    }
}
