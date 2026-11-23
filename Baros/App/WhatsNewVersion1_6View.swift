import SwiftUI

struct WhatsNewVersion1_6View: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            LaunchExperiencePage(
                systemImage: "figure.strengthtraining.traditional",
                title: "What's new in Baros 1.6",
                titleIdentifier: "LaunchExperienceTitle"
            ) {
                VStack(alignment: .leading, spacing: 20) {
                    LaunchExperienceFeatureRow(
                        systemImage: "heart.text.square",
                        title: "Save workouts to Apple Health",
                        detail: "Turn it on in Settings. Each workout shows up in Health and Fitness and counts toward your Activity."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "applewatch",
                        title: "Baros on Apple Watch",
                        detail: "Start a workout on your iPhone and your Watch shows live heart rate and time, then saves it to Health."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "heart.fill",
                        title: "Live heart rate",
                        detail: "See your heart rate in the workout header from your Apple Watch, AirPods Pro 3, or a Bluetooth strap."
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
