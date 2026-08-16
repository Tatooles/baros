import SwiftUI

/// The stable launch-experience boundary for onboarding.
///
/// The current implementation is a one-step introduction. A future multi-step
/// onboarding flow can replace this view without changing launch coordination
/// or release-note selection.
struct OnboardingFlow: View {
    let onCompleted: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .accessibilityHidden(true)

                    Text("Welcome to Baros")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("LaunchExperienceTitle")

                    Text("Log your lifts in seconds. Everything is saved on this iPhone, with optional cloud sync when you sign in.")
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
                        systemImage: "bolt.fill",
                        title: "Fast workout logging",
                        detail: "Start a workout and log sets in a couple of taps — no network needed."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "clock.arrow.circlepath",
                        title: "Your history stays put",
                        detail: "Every finished workout is saved on this iPhone, even offline."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "icloud",
                        title: "Optional cloud sync",
                        detail: "Sign in to back up finished workouts, exercises, and settings."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "lock.shield",
                        title: "Control your data",
                        detail: "Export history and manage privacy from Settings."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.bottom, AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(action: onCompleted) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(AppTheme.brandAccentFill)
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.vertical, AppTheme.shellPadding)
            .accessibilityIdentifier("LaunchExperiencePrimaryButton")
        }
        .interactiveDismissDisabled()
    }
}
