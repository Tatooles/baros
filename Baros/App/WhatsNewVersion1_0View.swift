import SwiftUI

/// The release sheet shipped for Baros 1.0.
///
/// This view deliberately owns its complete layout so future releases can use
/// entirely different designs without expanding a shared content schema.
struct WhatsNewVersion1_0View: View {
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .accessibilityHidden(true)

                    Text("What's new in Baros")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("LaunchExperienceTitle")

                    Text("The first release of Baros: fast workout logging, a safe local history, and optional cloud sync.")
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
                        systemImage: "iphone",
                        title: "Offline-first logging",
                        detail: "Start and finish workouts even when the network is unavailable."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "icloud",
                        title: "Cloud sync",
                        detail: "Sign in to sync completed workouts, exercises, and settings."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "square.and.arrow.up",
                        title: "Data controls",
                        detail: "Export workout history and manage privacy from Settings."
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
