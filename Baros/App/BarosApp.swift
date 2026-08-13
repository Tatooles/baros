import ClerkKit
@preconcurrency import ConvexMobile
import SwiftData
import SwiftUI
import UIKit

@main
struct BarosApp: App {
    private let modelContainer: ModelContainer
    private let convexClient: ConvexClientWithAuth<String>
    private let uiTestSyncOwner: String?
    private let uiTestSyncFailureMessage: String?
    private let observesNetworkRecovery: Bool
    private let networkRecoveryActivity: NetworkRecoveryActivity
    private let networkPathObserver: NetworkPathObserver<
        NetworkRecoveryActivity.Candidate<CurrentOwnerCoordinator.NetworkRecoveryCandidate>
    >
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationState = AppNavigationState()
    @State private var activeWorkoutEngine = ActiveWorkoutEngine()
    @State private var syncScheduler: SyncScheduler
    @State private var currentOwnerCoordinator: CurrentOwnerCoordinator

    init() {
        let syncObservability = SentryRuntime.startIfEnabled()
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        let convexClient = ConvexClientFactory.makeAuthenticatedClient()
        self.convexClient = convexClient

        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("--uitest-disable-animations") {
            UIView.setAnimationsEnabled(false)
        }
        #endif
        let ownerLaunchConfiguration = CurrentOwnerLaunchConfiguration(arguments: arguments)
        observesNetworkRecovery = ownerLaunchConfiguration.observesNetworkRecovery
        let networkRecoveryActivity = NetworkRecoveryActivity()
        self.networkRecoveryActivity = networkRecoveryActivity
        uiTestSyncOwner = ownerLaunchConfiguration.fixedOwnerTokenIdentifier
        uiTestSyncFailureMessage = if let uiTestSyncOwner,
                                      arguments.contains("--uitest-show-sync-failure") {
            "Convex function sync:fetchChanges failed for token \(uiTestSyncOwner)"
        } else {
            nil
        }
        FirstRunExperienceStore.resetForUITestingIfRequested(arguments: arguments)
        FirstRunExperienceStore.markSeenForUITestingIfRequested(arguments: arguments)
        ExercisePickerSortPreferenceStore.resetForUITestingIfRequested(arguments: arguments)

        do {
            let useInMemoryStore = arguments.contains("--uitest-in-memory-store")
            if arguments.contains("--uitest-reset-persistent-store") {
                try ModelContainerFactory.resetPersistentStoreFiles()
            }
            let container = try ModelContainerFactory.makeModelContainer(
                isStoredInMemoryOnly: useInMemoryStore
            )
            if let uiTestSyncOwner {
                try SeedDataService.seedIfNeeded(
                    context: container.mainContext,
                    ownerTokenIdentifier: uiTestSyncOwner
                )
            } else {
                try SeedDataService.seedIfNeeded(
                    context: container.mainContext,
                    ownerlessScope: .allExisting
                )
            }
            #if DEBUG
            try UITestFixtureSeeder.seedFixtures(
                from: arguments,
                ownerTokenIdentifier: uiTestSyncOwner,
                context: container.mainContext
            )
            #endif
            modelContainer = container

            let syncScheduler = SyncScheduler(observability: syncObservability)
            switch ownerLaunchConfiguration.startupMode {
            case .live:
                syncScheduler.configure(
                    coordinator: SyncCoordinator(
                        client: ConvexSyncClient(client: convexClient),
                        observability: syncObservability
                    ),
                    modelContext: container.mainContext
                )
            case .restoreCachedOwner, .signedOut:
                syncScheduler.configure(modelContext: container.mainContext)
            case .fixedOwner:
                break
            }
            _syncScheduler = State(initialValue: syncScheduler)
            let currentOwnerCoordinator = CurrentOwnerCoordinator(
                authenticationClient: ConvexCurrentOwnerAuthenticationClient(
                    client: convexClient
                ),
                syncScheduler: syncScheduler,
                clerkSessionProvider: ClerkCurrentOwnerSessionProvider(),
                startupMode: ownerLaunchConfiguration.startupMode
            )
            _currentOwnerCoordinator = State(initialValue: currentOwnerCoordinator)
            networkPathObserver = NetworkPathObserver {
                networkRecoveryActivity.makeCandidate {
                    currentOwnerCoordinator.makeNetworkRecoveryCandidate()
                }
            }
        } catch {
            fatalError("Unable to initialize Baros persistence: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(
                navigationState: navigationState,
                activeWorkoutEngine: activeWorkoutEngine
            )
            .modelContainer(modelContainer)
            .environment(Clerk.shared)
            .environment(syncScheduler)
            .environment(
                \.syncRecoveryAction,
                SyncRecoveryAction { trigger in
                    currentOwnerCoordinator.requestSyncRecovery(for: trigger)
                }
            )
            .environment(
                \.accountDeletionFactory,
                AccountDeletionFactory.live(syncClient: ConvexSyncClient(client: convexClient))
            )
            .overlay(alignment: .bottom) {
                if uiTestSyncOwner != nil {
                    Text("UITestSyncRequestCount-\(syncScheduler.requestCount)")
                        .font(.caption2)
                        .accessibilityIdentifier("UITestSyncRequestCount")
                }
            }
            #if DEBUG
            .overlay(alignment: .topLeading) {
                ExerciseHistoryUITestMetricsOverlay()
            }
            #endif
            .task {
                currentOwnerCoordinator.start()
                networkRecoveryActivity.setActive(scenePhase == .active)
                if observesNetworkRecovery {
                    networkPathObserver.start { candidate in
                        networkRecoveryActivity.performIfCurrent(candidate) { ownerCandidate in
                            currentOwnerCoordinator.networkDidRecover(ownerCandidate)
                        }
                    }
                }
                if let uiTestSyncFailureMessage {
                    syncScheduler.recordFailureForTesting(message: uiTestSyncFailureMessage)
                }
            }
            .onChange(of: scenePhase) { _, newScenePhase in
                networkRecoveryActivity.setActive(newScenePhase == .active)
                guard newScenePhase == .active else { return }
                currentOwnerCoordinator.appDidEnterForeground()
            }
        }
    }
}

#if DEBUG
private struct ExerciseHistoryUITestMetricsOverlay: View {
    private let metrics = ExerciseHistoryUITestMetrics.shared
    @State private var displayedResolutionCount = 0
    @State private var displayedResolutionTimeMilliseconds = 0.0

    var body: some View {
        if metrics.isEnabled {
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    "resolutions=\(displayedResolutionCount) "
                        + "resolutionTimeMilliseconds=\(displayedResolutionTimeMilliseconds)"
                )
                .font(.caption2)
                .accessibilityIdentifier("UITestExerciseHistoryMetrics")

                Button("Refresh history metrics") {
                    displayedResolutionCount = metrics.resolutionCount
                    displayedResolutionTimeMilliseconds = metrics.resolutionTimeMilliseconds
                }
                .font(.caption2)
                .accessibilityIdentifier("UITestExerciseHistoryMetricsRefresh")
            }
        }
    }
}
#endif
