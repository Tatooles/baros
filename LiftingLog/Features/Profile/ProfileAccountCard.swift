import ClerkKit
import ClerkKitUI
import SwiftUI

struct ProfileAccountCard: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false

    private var forceSignedOutAuth: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-force-signed-out-auth")
    }

    private var displayState: AccountDisplayState {
        if forceSignedOutAuth {
            return .signedOut
        }

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
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayState.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("ProfileAccountTitle")

                    Text(displayState.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(displayState.isSignedIn ? 1 : 2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ProfileAccountSubtitle")
                }
                .layoutPriority(1)

                Spacer(minLength: 10)

                if displayState.isSignedIn {
                    UserButton()
                        .frame(minWidth: 36, minHeight: 36)
                        .accessibilityIdentifier("ProfileUserButton")
                } else {
                    Button {
                        authIsPresented = true
                    } label: {
                        Text(displayState.actionTitle)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppTheme.accentGradient)
                            .foregroundStyle(AppTheme.textPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ProfileSignInButton")
                }
            }
        }
        .prefetchClerkImages()
        .sheet(isPresented: $authIsPresented) {
            AuthView()
                .presentationDragIndicator(.visible)
        }
    }

    private static func fullName(firstName: String?, lastName: String?) -> String? {
        let name = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return name.isEmpty ? nil : name
    }
}
