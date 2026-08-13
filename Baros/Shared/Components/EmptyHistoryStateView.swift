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
        isRecoveringAuthentication: Bool = false,
        isAwaitingInitialRecovery: Bool = false
    ) -> Self {
        switch currentOwnerState {
        case .localOnly:
            return hasVisibleCompletedWorkouts ? .ordinaryEmpty : .signInRecovery
        case .resolving:
            return isRecoveringAuthentication || isAwaitingInitialRecovery ? .syncing : .ordinaryEmpty
        case .active:
            return isSyncing || isAwaitingInitialRecovery ? .syncing : .ordinaryEmpty
        }
    }
}

struct EmptyHistoryRecoveryActivity: Equatable {
    private(set) var isAwaitingInitialRecovery = false

    mutating func currentOwnerStateDidChange(
        from oldState: CurrentOwnerCoordinator.State,
        to newState: CurrentOwnerCoordinator.State,
        isRecoveringAuthentication: Bool
    ) {
        switch newState {
        case .localOnly:
            isAwaitingInitialRecovery = false
        case .resolving:
            if oldState == .localOnly, isRecoveringAuthentication {
                isAwaitingInitialRecovery = true
            }
        case .active:
            if oldState == .localOnly, isRecoveringAuthentication {
                isAwaitingInitialRecovery = true
            }
        }
    }

    mutating func syncDidChange(from wasSyncing: Bool, to isSyncing: Bool) {
        if isSyncing {
            isAwaitingInitialRecovery = true
        } else if wasSyncing {
            isAwaitingInitialRecovery = false
        }
    }

    mutating func authenticationRecoveryDidChange(
        from wasRecovering: Bool,
        to isRecovering: Bool,
        currentOwnerState: CurrentOwnerCoordinator.State,
        isSyncing: Bool
    ) {
        guard wasRecovering,
              !isRecovering,
              !isSyncing,
              case .resolving = currentOwnerState else {
            return
        }
        isAwaitingInitialRecovery = false
    }

    mutating func syncDidFinish() {
        isAwaitingInitialRecovery = false
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
    @State private var recoveryActivity = EmptyHistoryRecoveryActivity()
    #if DEBUG
    @State private var uiTestCurrentOwnerStateOverride: CurrentOwnerCoordinator.State?
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
            isRecoveringAuthentication: currentOwnerCoordinator.isRecoveringAuthentication,
            isAwaitingInitialRecovery: recoveryActivity.isAwaitingInitialRecovery
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
        .onChange(of: currentOwnerCoordinator.state, initial: true) { oldState, newState in
            recoveryActivity.currentOwnerStateDidChange(
                from: oldState,
                to: newState,
                isRecoveringAuthentication: currentOwnerCoordinator.isRecoveringAuthentication
            )
        }
        .onChange(of: syncScheduler.isSyncing) { wasSyncing, isSyncing in
            recoveryActivity.syncDidChange(from: wasSyncing, to: isSyncing)
        }
        .onChange(of: currentOwnerCoordinator.isRecoveringAuthentication) { wasRecovering, isRecovering in
            recoveryActivity.authenticationRecoveryDidChange(
                from: wasRecovering,
                to: isRecovering,
                currentOwnerState: currentOwnerCoordinator.state,
                isSyncing: syncScheduler.isSyncing
            )
        }
        .onChange(of: syncScheduler.lastSyncedAt) { _, lastSyncedAt in
            if lastSyncedAt != nil {
                recoveryActivity.syncDidFinish()
            }
        }
        .onChange(of: syncScheduler.lastFailure) { _, lastFailure in
            if lastFailure != nil {
                recoveryActivity.syncDidFinish()
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
        recoveryActivity.currentOwnerStateDidChange(
            from: .localOnly,
            to: resolvingState,
            isRecoveringAuthentication: true
        )
        uiTestCurrentOwnerStateOverride = resolvingState

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            let activeState = CurrentOwnerCoordinator.State.active(
                ownerTokenIdentifier: "issuer|ui_test_owner"
            )
            recoveryActivity.currentOwnerStateDidChange(
                from: resolvingState,
                to: activeState,
                isRecoveringAuthentication: true
            )
            uiTestCurrentOwnerStateOverride = activeState
            recoveryActivity.syncDidFinish()
        }
    }
    #endif
}
