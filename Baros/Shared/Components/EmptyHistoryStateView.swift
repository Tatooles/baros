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
        isAwaitingInitialRecovery: Bool = false
    ) -> Self {
        switch currentOwnerState {
        case .localOnly:
            return hasVisibleCompletedWorkouts ? .ordinaryEmpty : .signInRecovery
        case .resolving:
            return .syncing
        case .active:
            return isSyncing || isAwaitingInitialRecovery ? .syncing : .ordinaryEmpty
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
    @State private var isAwaitingInitialRecovery = false
    #if DEBUG
    @State private var uiTestPresentationOverride: EmptyHistoryPresentation?
    #endif

    private var presentation: EmptyHistoryPresentation {
        #if DEBUG
        if let uiTestPresentationOverride {
            return uiTestPresentationOverride
        }
        #endif

        return EmptyHistoryPresentation.make(
            currentOwnerState: currentOwnerCoordinator.state,
            isSyncing: syncScheduler.isSyncing,
            hasVisibleCompletedWorkouts: hasVisibleCompletedWorkouts,
            isAwaitingInitialRecovery: isAwaitingInitialRecovery
        )
    }

    var body: some View {
        Group {
            switch presentation {
            case .signInRecovery:
                SurfaceCard {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(AppTheme.accentBright)
                            .accessibilityHidden(true)

                        Text(recoveryTitle)
                            .font(.system(size: 20, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text(Self.recoveryMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.textSecondary)

                        Button("Sign In") {
                            authIsPresented = true
                        }
                        .buttonStyle(.glassProminent)
                        .tint(AppTheme.accentBright)
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
            switch newState {
            case .localOnly:
                isAwaitingInitialRecovery = false
            case .resolving:
                isAwaitingInitialRecovery = true
            case .active:
                if oldState == .localOnly {
                    isAwaitingInitialRecovery = true
                }
            }
        }
        .onChange(of: syncScheduler.isSyncing) { wasSyncing, isSyncing in
            if isSyncing {
                isAwaitingInitialRecovery = true
            } else if wasSyncing {
                isAwaitingInitialRecovery = false
            }
        }
        .onChange(of: syncScheduler.lastSyncedAt) { _, lastSyncedAt in
            if lastSyncedAt != nil {
                isAwaitingInitialRecovery = false
            }
        }
        .onChange(of: syncScheduler.lastFailure) { _, lastFailure in
            if lastFailure != nil {
                isAwaitingInitialRecovery = false
            }
        }
    }

    #if DEBUG
    private func simulateInitialRecoveryForUITesting() {
        // Drive only this view's presentation so the harness cannot create a
        // false Current Owner or touch persisted data and synchronization.
        uiTestPresentationOverride = .syncing
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            uiTestPresentationOverride = .ordinaryEmpty
        }
    }
    #endif
}
