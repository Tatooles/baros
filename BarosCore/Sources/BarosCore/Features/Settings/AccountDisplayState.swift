import Foundation

public struct AccountDisplayState: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let actionTitle: String
    public let isSignedIn: Bool

    public var accessibilityLabel: String {
        "\(title), \(subtitle)"
    }

    public static let signedOut = AccountDisplayState(
        title: "Local workout data",
        subtitle: "Sign in to keep your workouts backed up.",
        actionTitle: "Sign in",
        isSignedIn: false
    )

    public static func signedIn(fullName: String?, email: String?) -> AccountDisplayState {
        let trimmedName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedName.isEmpty {
            return AccountDisplayState(
                title: trimmedName,
                subtitle: trimmedEmail.isEmpty ? "Signed in" : trimmedEmail,
                actionTitle: "Manage account",
                isSignedIn: true
            )
        }

        if !trimmedEmail.isEmpty {
            return AccountDisplayState(
                title: trimmedEmail,
                subtitle: "Signed in",
                actionTitle: "Manage account",
                isSignedIn: true
            )
        }

        return AccountDisplayState(
            title: "Signed in",
            subtitle: "Account connected",
            actionTitle: "Manage account",
            isSignedIn: true
        )
    }
}
