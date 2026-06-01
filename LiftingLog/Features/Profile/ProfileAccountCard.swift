import ClerkKit
import ClerkKitUI
import SwiftUI

struct ProfileAccountCard: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false

    private var displayState: AccountDisplayState {
        guard let user = clerk.user else {
            return .signedOut
        }

        return .signedIn(
            fullName: Self.fullName(firstName: user.firstName, lastName: user.lastName),
            email: user.primaryEmailAddress?.emailAddress
        )
    }

    var body: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 14) {
                accountIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayState.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("ProfileAccountTitle")

                    Text(displayState.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ProfileAccountSubtitle")
                }

                Spacer(minLength: 10)

                UserButton(signedOutContent: {
                    Button {
                        authIsPresented = true
                    } label: {
                        Text(displayState.actionTitle)
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppTheme.accentGradient)
                            .foregroundStyle(AppTheme.textPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ProfileSignInButton")
                })
                .frame(minWidth: 36, minHeight: 36)
                .accessibilityIdentifier("ProfileUserButton")
            }
        }
        .prefetchClerkImages()
        .sheet(isPresented: $authIsPresented) {
            AuthView()
                .presentationDragIndicator(.visible)
        }
    }

    private var accountIcon: some View {
        Image(systemName: displayState.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(displayState.isSignedIn ? AppTheme.accentBright : AppTheme.textSecondary)
            .frame(width: 42, height: 42)
            .background(AppTheme.surfaceMuted)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private static func fullName(firstName: String?, lastName: String?) -> String? {
        let name = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return name.isEmpty ? nil : name
    }
}
