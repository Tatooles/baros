import Foundation

struct AccountDisplayState: Equatable {
    let title: String
    let subtitle: String
    let actionTitle: String
    let isSignedIn: Bool

    static let signedOut = AccountDisplayState(
        title: "Local workout data",
        subtitle: "Sign in to keep your workouts backed up.",
        actionTitle: "Sign in",
        isSignedIn: false
    )

    static func signedIn(fullName: String?, email: String?) -> AccountDisplayState {
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
