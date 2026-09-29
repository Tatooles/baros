import SwiftUI

/// The release sheet shipped for Baros 1.3. It shares onboarding's page
/// layout, including the inline navigation bar the layout expects, so both
/// launch experiences sit at the same position on screen.
struct WhatsNewVersion1_3View: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            LaunchExperiencePage(
                systemImage: "figure.strengthtraining.traditional",
                title: "What's new in Baros 1.3",
                summary: "Smarter logging while you lift, and a History that shows how far you've come.",
                titleIdentifier: "LaunchExperienceTitle",
                summaryIdentifier: "LaunchExperienceSummary"
            ) {
                VStack(alignment: .leading, spacing: 20) {
                    LaunchExperienceFeatureRow(
                        systemImage: "trophy",
                        title: "Records worth chasing",
                        detail: "See your actual and estimated strength records in Exercise History, with the set behind each one."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "magnifyingglass",
                        title: "Find any workout",
                        detail: "Search your history, and jump from an exercise straight to the workout where you did it."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "sparkles",
                        title: "Smarter set logging",
                        detail: "Baros suggests weight and reps from your earlier sets, and choosing an RPE completes the set."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Swap exercises mid-workout",
                        detail: "Equipment taken? Swap an exercise without losing your place, or create a new one right from search."
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
