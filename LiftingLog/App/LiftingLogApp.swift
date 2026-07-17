import ClerkKit
@preconcurrency import ConvexMobile
import SwiftData
import SwiftUI

@main
struct LiftingLogApp: App {
    private let modelContainer: ModelContainer
    private let convexClient: ConvexClientWithAuth<String>
    private let uiTestSyncOwner: String?
    private let uiTestSyncFailureMessage: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationState = AppNavigationState()
    @State private var activeWorkoutEngine = ActiveWorkoutEngine()
    @State private var syncScheduler: SyncScheduler
    @State private var syncOutboxTransaction: SyncOutboxTransaction
    @State private var currentOwnerCoordinator: CurrentOwnerCoordinator

    init() {
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        let convexClient = ConvexClientFactory.makeAuthenticatedClient()
        self.convexClient = convexClient

        let arguments = ProcessInfo.processInfo.arguments
        let ownerLaunchConfiguration = CurrentOwnerLaunchConfiguration(arguments: arguments)
        uiTestSyncOwner = ownerLaunchConfiguration.fixedOwnerTokenIdentifier
        uiTestSyncFailureMessage = if let uiTestSyncOwner,
                                      arguments.contains("--uitest-show-sync-failure") {
            "Convex function sync:fetchChanges failed for token \(uiTestSyncOwner)"
        } else {
            nil
        }
        FirstRunExperienceStore.resetForUITestingIfRequested(arguments: arguments)
        FirstRunExperienceStore.markSeenForUITestingIfRequested(arguments: arguments)

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

            let syncScheduler = SyncScheduler()
            switch ownerLaunchConfiguration.startupMode {
            case .live:
                syncScheduler.configure(
                    coordinator: SyncCoordinator(
                        client: ConvexSyncClient(client: convexClient)
                    ),
                    modelContext: container.mainContext
                )
            case .restoreCachedOwner, .signedOut:
                syncScheduler.configure(modelContext: container.mainContext)
            case .fixedOwner:
                break
            }
            _syncScheduler = State(initialValue: syncScheduler)
            _syncOutboxTransaction = State(
                initialValue: SyncOutboxTransaction(
                    modelContext: container.mainContext,
                    syncScheduler: syncScheduler
                )
            )
            _currentOwnerCoordinator = State(
                initialValue: CurrentOwnerCoordinator(
                    authenticationClient: ConvexCurrentOwnerAuthenticationClient(
                        client: convexClient
                    ),
                    syncScheduler: syncScheduler,
                    clerkSessionProvider: ClerkCurrentOwnerSessionProvider(),
                    startupMode: ownerLaunchConfiguration.startupMode
                )
            )
        } catch {
            fatalError("Unable to initialize Lifting Log persistence: \(error)")
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
            .environment(syncOutboxTransaction)
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
            .task {
                currentOwnerCoordinator.start()
                if let uiTestSyncFailureMessage {
                    syncScheduler.recordFailureForTesting(message: uiTestSyncFailureMessage)
                }
            }
            .onChange(of: scenePhase) { _, newScenePhase in
                guard newScenePhase == .active else { return }
                currentOwnerCoordinator.appDidEnterForeground()
            }
        }
    }
}
