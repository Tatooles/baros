import ClerkKit
import ClerkKitUI
import SwiftUI

/// The stable launch-experience boundary for onboarding.
///
/// A short introduction followed by an optional sign-in invitation. Every exit
/// that reaches the app calls `onCompleted`: continuing without an account, or
/// finishing sign-in. Cancelling sign-in returns to the invitation instead.
struct OnboardingFlow: View {
    let onCompleted: () -> Void

    @State private var showsSignInInvitation = false

    var body: some View {
        NavigationStack {
            // Both pages force the same inline navigation bar (see
            // LaunchExperiencePage) so its geometry does not change mid-push,
            // which would nudge page 2's content down after it lands.
            OnboardingIntroductionPage {
                showsSignInInvitation = true
            }
            .navigationDestination(isPresented: $showsSignInInvitation) {
                OnboardingSignInInvitationPage(onCompleted: onCompleted)
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct OnboardingIntroductionPage: View {
    let onContinue: () -> Void

    var body: some View {
        LaunchExperiencePage(
            systemImage: "figure.strengthtraining.traditional",
            title: "Welcome to Baros",
            summary: "A fast, simple log for your lifts.",
            titleIdentifier: "LaunchExperienceTitle",
            summaryIdentifier: "LaunchExperienceSummary"
        ) {
            VStack(alignment: .leading, spacing: 20) {
                LaunchExperienceFeatureRow(
                    systemImage: "bolt.fill",
                    title: "Log sets in seconds",
                    detail: "Start a workout and record each set in a couple of taps, even with no signal."
                )
                LaunchExperienceFeatureRow(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "See your progress as you lift",
                    detail: "Your last performance and personal records show up right where you log."
                )
                LaunchExperienceFeatureRow(
                    systemImage: "lock.shield",
                    title: "No account needed",
                    detail: "Workouts are saved on this iPhone. Export or delete them anytime in Settings."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            Button(action: onContinue) {
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

private struct OnboardingSignInInvitationPage: View {
    @Environment(Clerk.self) private var clerk
    let onCompleted: () -> Void

    @State private var authIsPresented = false
    #if DEBUG
    @State private var didSimulateAuthenticationForUITesting = false
    #endif

    /// Read when the auth sheet closes. `AuthView` dismisses itself once a
    /// session becomes active, so a signed-in user here means sign-in finished;
    /// no user means the person cancelled.
    private var isSignedIn: Bool {
        #if DEBUG
        if didSimulateAuthenticationForUITesting {
            return true
        }
        #endif
        if UITestAuthOverride.isForcedSignedOut {
            return false
        }
        return clerk.user != nil
    }

    var body: some View {
        LaunchExperiencePage(
            systemImage: "icloud",
            title: "Back up your workouts",
            summary: "Sign in to back up your workouts, exercises, and settings, and get them back on a new iPhone.",
            titleIdentifier: "OnboardingSignInTitle",
            summaryIdentifier: "OnboardingSignInSummary",
            focusesTitleOnAppear: true
        ) {
            EmptyView()
        } actions: {
            Button {
                authIsPresented = true
            } label: {
                Text("Sign in or create account")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(AppTheme.brandAccentFill)
            .accessibilityIdentifier("OnboardingSignInButton")

            Button(action: onCompleted) {
                Text("Continue without an account")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityIdentifier("OnboardingContinueWithoutAccountButton")

            Text("You can sign in anytime from Settings.")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("OnboardingSignInFootnote")
        }
        .sheet(isPresented: $authIsPresented, onDismiss: completeIfSignedIn) {
            ZStack(alignment: .bottom) {
                AuthView()
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier("OnboardingAuthView")

                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-simulate-onboarding-auth-success") {
                    Button("Simulate successful authentication") {
                        didSimulateAuthenticationForUITesting = true
                        authIsPresented = false
                    }
                    .font(.caption2)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("UITestSimulateOnboardingAuthenticationButton")
                }
                #endif
            }
        }
    }

    private func completeIfSignedIn() {
        guard isSignedIn else { return }
        onCompleted()
    }
}
