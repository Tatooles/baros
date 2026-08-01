import SwiftUI

/// The stable launch-experience boundary for onboarding.
///
/// The current implementation is a one-step introduction. A future multi-step
/// onboarding flow can replace this view without changing launch coordination
/// or release-note selection.
struct OnboardingFlow: View {
    let onCompleted: () -> Void

    var body: some View {
        LaunchExperienceContentSheet(
            title: "Welcome to Baros",
            summary: "Log your lifts in seconds. Everything is saved on this iPhone, with optional cloud sync when you sign in.",
            buttonTitle: "Continue",
            items: [
                LaunchExperienceItem(
                    id: "logging",
                    systemImage: "bolt.fill",
                    title: "Fast workout logging",
                    detail: "Start a workout and log sets in a couple of taps — no network needed."
                ),
                LaunchExperienceItem(
                    id: "history",
                    systemImage: "clock.arrow.circlepath",
                    title: "Your history stays put",
                    detail: "Every finished workout is saved on this iPhone, even offline."
                ),
                LaunchExperienceItem(
                    id: "sync",
                    systemImage: "icloud",
                    title: "Optional cloud sync",
                    detail: "Sign in to back up finished workouts, exercises, and settings."
                ),
                LaunchExperienceItem(
                    id: "data",
                    systemImage: "lock.shield",
                    title: "Control your data",
                    detail: "Export history and manage privacy from Settings."
                ),
            ],
            preventsInteractiveDismiss: true,
            primaryAction: onCompleted
        )
    }
}
