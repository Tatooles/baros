import ClerkKitUI
import SwiftUI

enum EmptyHistoryPresentation: Equatable {
    case signInRecovery
    case syncing
    case ordinaryEmpty

    static func make(
        currentOwnerState: CurrentOwnerCoordinator.State,
        isSyncing: Bool,
        hasVisibleCompletedWorkouts: Bool = false,
        isRecoveringAuthentication: Bool = false
    ) -> Self {
        switch currentOwnerState {
        case .localOnly:
            return hasVisibleCompletedWorkouts ? .ordinaryEmpty : .signInRecovery
        case .resolving(let ownerTokenIdentifier):
            return isRecoveringAuthentication && ownerTokenIdentifier != nil ? .syncing : .ordinaryEmpty
        case .active:
            return isRecoveringAuthentication || isSyncing ? .syncing : .ordinaryEmpty
        }
    }
}

struct EmptyHistoryStateView: View {
    static let recoveryMessage = "Sign in to sync workouts saved to your account and keep future workouts backed up."

    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    let recoveryTitle: String
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
            case .signInRecovery:
                SurfaceCard {
                    VStack(spacing: 12) {
                        Text(recoveryTitle)
                            .font(.system(size: 20, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text(Self.recoveryMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.textSecondary)

                        AccountSignInButton {
                            authIsPresented = true
                        }
                        .accessibilityIdentifier("EmptyHistorySignInButton")
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("EmptyHistorySignInPrompt")

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
