import ClerkKitUI
import SwiftUI

enum EmptyHistoryPresentation: Equatable {
    /// Someone signed in on this iPhone before; their workouts are hidden until they sign back in.
    case signedOutOwner(SignedOutOwnerData)
    /// Nobody has signed in on this iPhone yet. Offer sign-in for people moving from another device.
    case firstTimeSignIn
    case syncing
    case ordinaryEmpty

    static func make(
        currentOwnerState: CurrentOwnerCoordinator.State,
        isSyncing: Bool,
        signedOutOwnerData: SignedOutOwnerData? = nil,
        hasVisibleCompletedWorkouts: Bool = false,
        isRecoveringAuthentication: Bool = false
    ) -> Self {
        switch currentOwnerState {
        case .localOnly:
            if let signedOutOwnerData {
                return .signedOutOwner(signedOutOwnerData)
            }
            return hasVisibleCompletedWorkouts ? .ordinaryEmpty : .firstTimeSignIn
        case .resolving(let ownerTokenIdentifier):
            return isRecoveringAuthentication && ownerTokenIdentifier != nil ? .syncing : .ordinaryEmpty
        case .active:
            return isRecoveringAuthentication || isSyncing ? .syncing : .ordinaryEmpty
        }
    }
}

struct EmptyHistoryStateView: View {
    static let signedOutTitle = "You're signed out"

    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    let emptyTitle: String
    let emptyMessage: String
    var hasVisibleCompletedWorkouts = false
    @State private var authIsPresented = false
    #if DEBUG
    @State private var uiTestCurrentOwnerStateOverride: CurrentOwnerCoordinator.State?
    @State private var uiTestIsRecoveringAuthenticationOverride: Bool?
    #endif

    private var presentation: EmptyHistoryPresentation {
        #if DEBUG
        let currentOwnerState = uiTestCurrentOwnerStateOverride
            ?? currentOwnerCoordinator.state
        #else
        let currentOwnerState = currentOwnerCoordinator.state
        #endif

        return EmptyHistoryPresentation.make(
            currentOwnerState: currentOwnerState,
            isSyncing: syncScheduler.isSyncing,
            signedOutOwnerData: syncScheduler.signedOutOwnerData,
            hasVisibleCompletedWorkouts: hasVisibleCompletedWorkouts,
            isRecoveringAuthentication: {
                #if DEBUG
                uiTestIsRecoveringAuthenticationOverride
                    ?? currentOwnerCoordinator.isRecoveringAuthentication
                #else
                currentOwnerCoordinator.isRecoveringAuthentication
                #endif
            }()
        )
    }

    var body: some View {
        Group {
            switch presentation {
            case .signedOutOwner(let signedOutOwnerData):
                SurfaceCard {
                    VStack(spacing: 12) {
                        Text(Self.signedOutTitle)
                            .font(.system(size: 20, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text(signedOutOwnerData.signInMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityIdentifier("EmptyHistorySignedOutMessage")

                        AccountSignInButton {
                            authIsPresented = true
                        }
                        .accessibilityIdentifier("EmptyHistorySignInButton")
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("EmptyHistorySignInPrompt")

            case .firstTimeSignIn:
                SurfaceCard {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(emptyTitle)
                            .font(.system(size: 20, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text(emptyMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.textSecondary)

                        Text("Already have an account?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 4)

                        AccountSignInButton {
                            authIsPresented = true
                        }
                        .accessibilityIdentifier("EmptyHistorySignInButton")
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("EmptyHistoryFirstTimePrompt")

            case .syncing:
                LoadingStateView(title: "Syncing your workout history…")
                    .accessibilityIdentifier("EmptyHistorySyncingState")

            case .ordinaryEmpty:
                EmptyStateView(title: emptyTitle, message: emptyMessage)
            }
        }
        .sheet(isPresented: $authIsPresented) {
            ZStack(alignment: .bottom) {
                AuthView()
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier("EmptyHistoryAuthView")

                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--uitest-simulate-empty-history-auth-recovery") {
                    Button("Simulate successful authentication") {
                        authIsPresented = false
                        simulateInitialRecoveryForUITesting()
                    }
                    .font(.caption2)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("UITestSimulateEmptyHistoryAuthenticationButton")
                }
                #endif
            }
        }
    }

    #if DEBUG
    private func simulateInitialRecoveryForUITesting() {
        // Exercise this view's real owner-transition policy without mutating
        // the Current Owner, persisted data, or synchronization.
        let resolvingState = CurrentOwnerCoordinator.State.resolving(
            ownerTokenIdentifier: "issuer|ui_test_owner"
        )
        uiTestIsRecoveringAuthenticationOverride = true
        uiTestCurrentOwnerStateOverride = resolvingState

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let activeState = CurrentOwnerCoordinator.State.active(
                ownerTokenIdentifier: "issuer|ui_test_owner"
            )
            uiTestCurrentOwnerStateOverride = activeState
            uiTestIsRecoveringAuthenticationOverride = false
        }
    }
    #endif
}
