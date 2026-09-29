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
            OnboardingIntroductionPage {
                showsSignInInvitation = true
            }
            .toolbar(.hidden, for: .navigationBar)
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
        OnboardingPage(
            systemImage: "figure.strengthtraining.traditional",
            title: "Welcome to Baros",
            summary: "A fast, simple log for your lifts.",
            titleIdentifier: "LaunchExperienceTitle",
            summaryIdentifier: "LaunchExperienceSummary",
            topPadding: 48
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
        OnboardingPage(
            systemImage: "icloud",
            title: "Back up your workouts",
            summary: "Sign in to back up your workouts, exercises, and settings, and get them back on a new iPhone.",
            titleIdentifier: "OnboardingSignInTitle",
            summaryIdentifier: "OnboardingSignInSummary",
            topPadding: 16,
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

            Text("You can sign in anytime from Profile.")
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

/// Shared layout for onboarding pages: hero symbol, title, summary, optional
/// content, and actions. Actions pin to the bottom edge, except at
/// accessibility text sizes, where they scroll with the content so large
/// labels never crowd the page out.
private struct OnboardingPage<Content: View, Actions: View>: View {
    let systemImage: String
    let title: String
    let summary: String
    let titleIdentifier: String
    let summaryIdentifier: String
    let topPadding: CGFloat
    var focusesTitleOnAppear = false
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isTitleFocused)
                        .accessibilityIdentifier(titleIdentifier)

                    Text(summary)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(summaryIdentifier)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, topPadding)

                content

                if dynamicTypeSize.isAccessibilitySize {
                    actionStack
                }
            }
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.bottom, AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if !dynamicTypeSize.isAccessibilitySize {
                actionStack
                    .padding(.horizontal, AppTheme.shellPadding + 8)
                    .padding(.vertical, AppTheme.shellPadding)
            }
        }
        .onAppear {
            if focusesTitleOnAppear {
                isTitleFocused = true
            }
        }
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            actions
        }
    }
}
