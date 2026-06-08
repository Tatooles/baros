import SwiftData
import SwiftUI
import ClerkKit

@main
struct LiftingLogApp: App {
    private let modelContainer: ModelContainer
    @State private var navigationState = AppNavigationState()
    @State private var activeWorkoutEngine = ActiveWorkoutEngine()
    @State private var syncScheduler = SyncScheduler()
    @State private var convexClient = ConvexClientFactory.makeAuthenticatedClient()
    @State private var syncAuthTask: Task<Void, Never>?

    init() {
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)

        do {
            let arguments = ProcessInfo.processInfo.arguments
            let useInMemoryStore = arguments.contains("--uitest-in-memory-store")
            if arguments.contains("--uitest-reset-persistent-store") {
                try ModelContainerFactory.resetPersistentStoreFiles()
            }
            let container = try ModelContainerFactory.makeModelContainer(isStoredInMemoryOnly: useInMemoryStore)
            try SeedDataService.seedIfNeeded(context: container.mainContext)
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
            .task {
                configureSyncIfNeeded()
            }
        }
    }

    private func configureSyncIfNeeded() {
        guard syncAuthTask == nil else { return }

        let syncClient = ConvexSettingsExerciseSyncClient(client: convexClient)
        let coordinator = SettingsExerciseSyncCoordinator(client: syncClient)
        syncScheduler.configure(coordinator: coordinator, modelContext: modelContainer.mainContext)

        syncAuthTask = Task { @MainActor in
            for await state in convexClient.authState.values {
                switch state {
                case .loading:
                    break
                case .unauthenticated:
                    syncScheduler.currentOwnerTokenIdentifier = nil
                case .authenticated:
                    syncScheduler.currentOwnerTokenIdentifier = await resolveOwnerTokenIdentifier()
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
