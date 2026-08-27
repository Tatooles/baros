import SwiftUI

/// The release sheet shipped for Baros 1.2.
struct WhatsNewVersion1_2View: View {
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .accessibilityHidden(true)

                    Text("What's new in Baros 1.2")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("LaunchExperienceTitle")

                    Text("Meet a refreshed Baros with more flexible workouts, progress at a glance, and an easier way to start from your history.")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("LaunchExperienceSummary")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 20) {
                    LaunchExperienceFeatureRow(
                        systemImage: "arrow.down.right.and.arrow.up.left",
                        title: "Keep your workout close",
                        detail: "Minimize an active workout, move around Baros, and choose Return to Workout when you’re ready."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "iphone",
                        title: "Progress at a glance",
                        detail: "See your active workout on the Lock Screen and, on supported iPhones, in the Dynamic Island."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "clock.arrow.circlepath",
                        title: "Build from a past workout",
                        detail: "Review a completed workout, then use its exercise and set structure to start a new one."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.bottom, AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(action: onDismiss) {
                Text("Got It")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(AppTheme.brandAccentFill)
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.vertical, AppTheme.shellPadding)
            .accessibilityIdentifier("LaunchExperiencePrimaryButton")
        }
    }
}
