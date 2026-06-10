import SwiftData
import SwiftUI
import ClerkKit

@main
struct LiftingLogApp: App {
    private let modelContainer: ModelContainer
    private let uiTestSyncOwner: String?
    @State private var navigationState = AppNavigationState()
    @State private var activeWorkoutEngine = ActiveWorkoutEngine()
    @State private var syncScheduler = SyncScheduler()
    @State private var convexClient = ConvexClientFactory.makeAuthenticatedClient()
    @State private var syncAuthTask: Task<Void, Never>?

    init() {
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        let arguments = ProcessInfo.processInfo.arguments
        let uiTestSyncOwnerIndex = arguments.firstIndex(of: "--uitest-sync-owner")
        uiTestSyncOwner = uiTestSyncOwnerIndex.flatMap { index -> String? in
            let nextIndex = arguments.index(after: index)
            return nextIndex < arguments.endIndex ? arguments[nextIndex] : nil
        }

        do {
            let useInMemoryStore = arguments.contains("--uitest-in-memory-store")
            if arguments.contains("--uitest-reset-persistent-store") {
                try ModelContainerFactory.resetPersistentStoreFiles()
            }
            let container = try ModelContainerFactory.makeModelContainer(isStoredInMemoryOnly: useInMemoryStore)
            if let uiTestSyncOwner {
                try SeedDataService.seedIfNeeded(context: container.mainContext, ownerTokenIdentifier: uiTestSyncOwner)
            } else {
                try SeedDataService.seedIfNeeded(context: container.mainContext, ownerlessScope: .allExisting)
            }
            modelContainer = container
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
            .overlay(alignment: .bottom) {
                if uiTestSyncOwner != nil {
                    Text("UITestSyncRequestCount-\(syncScheduler.requestCount)")
                        .font(.caption2)
                        .accessibilityIdentifier("UITestSyncRequestCount")
                }
            }
            .task {
                if let uiTestSyncOwner {
                    syncScheduler.currentOwnerTokenIdentifier = uiTestSyncOwner
                    return
                }
                configureSyncIfNeeded()
            }
        }
    }

    private func configureSyncIfNeeded() {
        guard syncAuthTask == nil else { return }

        let syncClient = ConvexSyncClient(client: convexClient)
        let coordinator = SyncCoordinator(client: syncClient)
        syncScheduler.configure(coordinator: coordinator, modelContext: modelContainer.mainContext)

        syncAuthTask = Task { @MainActor in
            for await state in convexClient.authState.values {
                switch state {
                case .loading:
                    break
                case .unauthenticated:
                    syncScheduler.currentOwnerTokenIdentifier = nil
                    syncScheduler.seedDefaultsForLocalMode()
                case .authenticated:
                    guard let ownerTokenIdentifier = await resolveOwnerTokenIdentifier() else {
                        break
                    }
                    syncScheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
                    syncScheduler.seedDefaultsForCurrentOwner()
                    syncScheduler.requestSync()
                }
            }
        }
    }

    private func resolveOwnerTokenIdentifier() async -> String? {
        let publisher = convexClient.subscribe(
            to: "authSmoke:me",
            yielding: ConvexAuthSmokeIdentity.self
        )

        do {
            for try await identity in publisher.values {
                return identity.tokenIdentifier
            }
        } catch {
            return nil
        }

        return nil
    }
}

private struct ConvexAuthSmokeIdentity: Decodable {
    let tokenIdentifier: String
}
