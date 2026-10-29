import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

/// Recovery is derived from durable workouts, so it also works after relaunch
/// and with legacy records. No recovery flags or new workout states are saved.
struct WorkoutRecoveryNotice: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accountSignOutAction) private var signOut
    @Environment(ActiveWorkoutEngine.self) private var engine
    @Environment(CurrentOwnerCoordinator.self) private var currentOwner
    @Query private var sessions: [WorkoutSession]
    @State private var showsSignIn = false
    @State private var showsDiscard = false
    @State private var targetID: UUID?
    @State private var expectedOwner: String?
    @State private var errorMessage: String?

    private var active: [WorkoutSession] {
        WorkoutRecovery.activeSessions(in: sessions)
    }
    private var hidden: [WorkoutSession] {
        WorkoutRecovery.hiddenSessions(in: sessions, owner: currentOwner.localDataOwnerTokenIdentifier)
    }
    private var needsRecovery: Bool {
        if case .resolving(ownerTokenIdentifier: nil) = currentOwner.state { return false }
        return !hidden.isEmpty || active.count > 1
    }

    var body: some View {
        if needsRecovery {
            VStack(alignment: .leading, spacing: 10) {
                Text("Unfinished Workout").font(.headline)
                Text(hidden.isEmpty
                    ? "More than one unfinished workout is saved on this iPhone. Resolve them before starting another."
                    : "An unfinished workout is saved on this iPhone. Sign into its account to continue, or discard it to start another.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !hidden.isEmpty {
                    if currentOwner.localDataOwnerTokenIdentifier != nil {
                        AccountTransitionButton(destination: .signOut) {
                            try await signOut()
                            showsSignIn = true
                        } label: { Text("Sign Out to Recover Workout") }
                        .accessibilityIdentifier("WorkoutRecoverySignOutButton")
                    } else {
                        Button("Sign In to Recover Workout") { showsSignIn = true }
                            .accessibilityIdentifier("WorkoutRecoverySignInButton")
                    }
                }
                Button("Discard Unfinished Workout", role: .destructive) {
                    targetID = (hidden.first ?? active.first)?.id
                    expectedOwner = currentOwner.localDataOwnerTokenIdentifier
                    showsDiscard = true
                }
                .accessibilityIdentifier("WorkoutRecoveryDiscardButton")
            }
            .buttonStyle(.borderless)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            .alert("Discard unfinished workout?", isPresented: $showsDiscard) {
                Button("Discard Workout", role: .destructive) { discard() }
                Button("Cancel", role: .cancel) { targetID = nil }
            } message: {
                Text("This permanently discards one unfinished workout saved on this iPhone. It won’t appear in workout history. Other saved workouts are kept.")
            }
            .sheet(isPresented: $showsSignIn) {
                AuthView().presentationDragIndicator(.visible)
                    .accessibilityIdentifier("WorkoutRecoveryAuthView")
            }
            .alert("Couldn’t Discard Workout", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) { errorMessage = nil } }
                message: { Text(errorMessage ?? "Try again.") }
        }
    }

    private func discard() {
        do {
            try WorkoutRecovery.discard(id: targetID, expectedOwner: expectedOwner,
                currentOwner: currentOwner.localDataOwnerTokenIdentifier,
                engine: engine, context: context, save: { context in
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-fail-account-workout-save") {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
                }
                #endif
                try context.save()
            })
        } catch { errorMessage = "The workout could not be discarded. It is still saved on this iPhone. Try again." }
    }
}

/// A real seam for the live Clerk action and deterministic session-event tests.
struct AccountSignOutAction {
    let perform: @MainActor () async throws -> Void
    static let live = AccountSignOutAction {
        try await Clerk.shared.auth.signOut(sessionId: Clerk.shared.session?.id)
    }

    @MainActor
    func callAsFunction() async throws { try await perform() }
}

private struct AccountSignOutActionKey: EnvironmentKey {
    static let defaultValue = AccountSignOutAction.live
}

extension EnvironmentValues {
    var accountSignOutAction: AccountSignOutAction {
        get { self[AccountSignOutActionKey.self] }
        set { self[AccountSignOutActionKey.self] = newValue }
    }
}
