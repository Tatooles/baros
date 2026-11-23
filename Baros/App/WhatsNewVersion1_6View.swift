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
                        detail: "Turn it on in Settings, and with your permission, workouts you finish show up in Health and Fitness."
                    )
                    LaunchExperienceFeatureRow(
                        systemImage: "applewatch",
                        title: "Baros on Apple Watch",
                        detail: "With Apple Health on, the Baros Watch app, and your Watch nearby, start a workout on your iPhone and see live heart rate and time on your wrist."
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
