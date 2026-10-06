import ClerkKit
import ClerkKitUI
import SwiftUI

enum UITestAuthOverride {
    static var isForcedSignedOut: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-force-signed-out-auth")
    }

    static var isForcedSignedIn: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-force-signed-in-auth")
    }
}

struct SettingsAccountRow: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedSheet: PresentedSheet?

    private enum PresentedSheet: String, Identifiable {
        case auth
        case userProfile

        var id: String { rawValue }
    }

    private var displayState: AccountDisplayState {
        if UITestAuthOverride.isForcedSignedOut {
            return .signedOut
        }

        if UITestAuthOverride.isForcedSignedIn {
            return .signedIn(fullName: "UI Test Account", email: "ui-test@example.com")
        }

        guard let user = clerk.user else {
            return .signedOut
        }

        return .signedIn(
            fullName: Self.fullName(firstName: user.firstName, lastName: user.lastName),
            email: user.primaryEmailAddress?.emailAddress
        )
    }

    private var hasPendingSessionTasks: Bool {
        clerk.session?.tasks?.isEmpty == false
    }

    var body: some View {
        Button {
            // Match Clerk's UserButton: unfinished session tasks resume sign-in instead of the profile.
            presentedSheet = displayState.isSignedIn && !hasPendingSessionTasks ? .userProfile : .auth
        } label: {
            rowLayout {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayState.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("SettingsAccountTitle")

                    Text(displayState.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(displayState.isSignedIn ? 1 : nil)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("SettingsAccountSubtitle")
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }

                if !displayState.isSignedIn {
                    Text(displayState.actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccountRowButtonStyle(showsDisclosure: displayState.isSignedIn))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(displayState.isSignedIn ? displayState.actionTitle : displayState.subtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(displayState.isSignedIn ? "SettingsManageAccountButton" : "SettingsSignInButton")
        .prefetchClerkImages()
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .auth:
                AuthView()
                    .presentationDragIndicator(.visible)
            case .userProfile:
                UserProfileView()
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: clerk.user) { _, user in
            // Signing out from the profile sheet leaves nothing to show there.
            if user == nil, presentedSheet == .userProfile {
                presentedSheet = nil
            }
        }
    }

    /// Accessibility sizes stack the row so the name and copy keep the full row width.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
    }

    private var accessibilityLabel: String {
        displayState.isSignedIn
            ? "\(displayState.title), \(displayState.subtitle)"
            : displayState.actionTitle
    }

    @ViewBuilder
    private var avatar: some View {
        let size: CGFloat = 44

        if displayState.isSignedIn, let imageURL = clerk.user.flatMap({ URL(string: $0.imageUrl) }) {
            AsyncImage(url: imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                avatarPlaceholder
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarPlaceholder
                .frame(width: size, height: size)
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: displayState.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(AppTheme.brandAccentForeground)
    }

    private static func fullName(firstName: String?, lastName: String?) -> String? {
        let name = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return name.isEmpty ? nil : name
    }
}

/// A Form row button that keeps row highlighting and, when navigable, the native disclosure chevron.
private struct AccountRowButtonStyle: ButtonStyle {
    let showsDisclosure: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }
        }
        .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
