import SwiftUI

struct WhatsNewVersion1_5View: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            LaunchExperiencePage(
                systemImage: "figure.strengthtraining.traditional",
                title: "What's new in Baros 1.5",
                titleIdentifier: "LaunchExperienceTitle"
            ) {
                VStack(alignment: .leading, spacing: 20) {
                    LaunchExperienceFeatureRow(
                        systemImage: "list.bullet.clipboard",
                        title: "Workout templates",
                        detail: "Save a workout as a template and start from it next time."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "link",
                        title: "Supersets",
                        detail: "Group exercises so each round is checked and rested together."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "trophy",
                        title: "Records that tell the story",
                        detail: "See your heaviest rep, your estimated 1RM over time, and the set behind each record."
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
