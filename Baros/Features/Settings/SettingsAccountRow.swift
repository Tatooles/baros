import BarosCore
import ClerkKit
import ClerkKitUI
import SwiftUI
import SwiftData

enum UITestAuthOverride {
    static var isForcedSignedOut: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-force-signed-out-auth")
    }

    static var isForcedSignedIn: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-force-signed-in-auth")
    }
}

enum SettingsAccountSheet: String, Identifiable {
    case auth
    case userProfile
    case account

    var id: String { rawValue }
}

@MainActor
private func accountDisplayState(clerk: Clerk) -> AccountDisplayState {
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
        fullName: accountFullName(firstName: user.firstName, lastName: user.lastName),
        email: user.primaryEmailAddress?.emailAddress
    )
}

@MainActor
private func hasPendingSessionTasks(clerk: Clerk) -> Bool {
    clerk.session?.tasks?.isEmpty == false
}

private func accountFullName(firstName: String?, lastName: String?) -> String? {
    let name = [firstName, lastName]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    return name.isEmpty ? nil : name
}

struct SettingsAccountRow: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var workouts: [WorkoutSession]
    /// Presented by `settingsAccountSheets(_:)` on the Settings Form. On iOS 26.4,
    /// a sheet attached inside a Form row loops in SwiftUI updates and never appears.
    @Binding var presentedSheet: SettingsAccountSheet?

    private var displayState: AccountDisplayState {
        accountDisplayState(clerk: clerk)
    }

    var body: some View {
        Button {
            if displayState.isSignedIn {
                presentedSheet = workouts.contains { $0.status == .active && !$0.isDeleted }
                    ? .account : (hasPendingSessionTasks(clerk: clerk) ? .auth : .userProfile)
            } else {
                presentedSheet = .auth
            }
        } label: {
            rowLayout {
                if dynamicTypeSize.isAccessibilitySize {
                    avatar
                    identity
                } else {
                    Label {
                        identity
                    } icon: {
                        avatar
                    }

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
        .accessibilityLabel(displayState.accessibilityLabel)
        .accessibilityHint(displayState.actionTitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(displayState.isSignedIn ? "SettingsManageAccountButton" : "SettingsSignInButton")
        .prefetchClerkImages()
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayState.title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("SettingsAccountTitle")

            Text(displayState.subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(displayState.isSignedIn ? 1 : nil)
                .truncationMode(.middle)
                .accessibilityIdentifier("SettingsAccountSubtitle")
        }
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))
    }

    @ViewBuilder
    private var avatar: some View {
        let size: CGFloat = dynamicTypeSize.isAccessibilitySize ? 44 : 32

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
}

extension View {
    func settingsAccountSheets(_ presentedSheet: Binding<SettingsAccountSheet?>) -> some View {
        modifier(SettingsAccountSheets(presentedSheet: presentedSheet))
    }
}

private struct SettingsAccountSheets: ViewModifier {
    @Environment(ActiveWorkoutEngine.self) private var engine
    @Environment(CurrentOwnerCoordinator.self) private var currentOwner
    @Environment(\.accountSignOutAction) private var signOut
    @Environment(Clerk.self) private var clerk
    @Binding var presentedSheet: SettingsAccountSheet?

    private var displayState: AccountDisplayState {
        accountDisplayState(clerk: clerk)
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .auth:
                    AuthView()
                        .presentationDragIndicator(.visible)
                case .userProfile:
                    UserProfileView()
                        .presentationDragIndicator(.visible)
                        .onAppear { engine.isAccountManagementPresented = true }
                        .onDisappear { engine.isAccountManagementPresented = false }
                case .account:
                    NavigationStack {
                        Form {
                            Section {
                                Text(displayState.title).font(.headline)
                                Text(displayState.subtitle).foregroundStyle(.secondary)
                            }
                            Section {
                                AccountTransitionButton(destination: .manageAccount) {
                                    presentedSheet = hasPendingSessionTasks(clerk: clerk) ? .auth : .userProfile
                                }
                                .accessibilityIdentifier("AccountManageProfileButton")
                                AccountTransitionButton(destination: .signOut, role: .destructive) {
                                    try await signOut()
                                    presentedSheet = nil
                                }
                                .accessibilityIdentifier("AccountSignOutButton")
                            }
                        }
                        .navigationTitle("Account")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { presentedSheet = nil }
                            }
                        }
                    }
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: currentOwner.localDataOwnerTokenIdentifier) { _, _ in
                presentedSheet = nil
            }
            .onChange(of: clerk.session?.id) { _, _ in
                if presentedSheet == .userProfile || presentedSheet == .account { presentedSheet = nil }
            }
            .onChange(of: clerk.user) { _, user in
                if user == nil, presentedSheet == .userProfile || presentedSheet == .account {
                    presentedSheet = nil
                }
            }
    }
}

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
