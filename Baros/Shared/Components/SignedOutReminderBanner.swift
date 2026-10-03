import ClerkKitUI
import SwiftUI

/// Tells someone who signed in on this iPhone before that they're signed out
/// and their workouts are still saved, until they dismiss it or sign back in.
struct SignedOutReminderBanner: View {
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @State private var authIsPresented = false
    var bottomSpacing: CGFloat = 0

    var body: some View {
        if let signedOutOwnerData = SignedOutReminderPresentation.bannerData(
            currentOwnerState: currentOwnerCoordinator.state,
            signedOutOwnerData: syncScheduler.signedOutOwnerData,
            isDismissed: syncScheduler.isSignedOutReminderDismissed
        ) {
            SurfaceCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(EmptyHistoryStateView.signedOutTitle)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(signedOutOwnerData.signInMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("SignedOutReminderMessage")

                        AccountSignInButton {
                            authIsPresented = true
                        }
                        .padding(.top, 8)
                        .accessibilityIdentifier("SignedOutReminderSignInButton")
                    }

                    Spacer(minLength: 0)

                    Button {
                        withAnimation {
                            syncScheduler.dismissSignedOutReminder()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -12)
                    .padding(.trailing, -12)
                    .accessibilityLabel("Dismiss")
                    .accessibilityIdentifier("SignedOutReminderDismissButton")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("SignedOutReminderBanner")
            .padding(.bottom, bottomSpacing)
            .sheet(isPresented: $authIsPresented) {
                AuthView()
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier("SignedOutReminderAuthView")
            }
        }
    }
}
