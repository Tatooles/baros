import SwiftData
import SwiftUI
import ClerkKit
@preconcurrency import ConvexMobile

@main
struct LiftingLogApp: App {
    private let modelContainer: ModelContainer
    private let convexClient: ConvexClientWithAuth<String>
    private let uiTestSyncOwner: String?
    private let uiTestForcesSignedOutAuth: Bool
    private let uiTestRestoresCachedSyncOwner: Bool
    private let uiTestRestoresCachedSyncOwnerSubject: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationState = AppNavigationState()
    @State private var activeWorkoutEngine = ActiveWorkoutEngine()
    @State private var syncScheduler = SyncScheduler()
    @State private var syncAuthTask: Task<Void, Never>?

    init() {
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        convexClient = ConvexClientFactory.makeAuthenticatedClient()
        let arguments = ProcessInfo.processInfo.arguments
        FirstRunExperienceStore.resetForUITestingIfRequested(arguments: arguments)
        FirstRunExperienceStore.markSeenForUITestingIfRequested(arguments: arguments)
        uiTestForcesSignedOutAuth = arguments.contains("--uitest-force-signed-out-auth")
        uiTestRestoresCachedSyncOwner = arguments.contains("--uitest-restore-cached-sync-owner")
        let uiTestSyncOwnerIndex = arguments.firstIndex(of: "--uitest-sync-owner")
        uiTestSyncOwner = uiTestSyncOwnerIndex.flatMap { index -> String? in
            let nextIndex = arguments.index(after: index)
            return nextIndex < arguments.endIndex ? arguments[nextIndex] : nil
        }
        let uiTestRestoreSubjectIndex = arguments.firstIndex(of: "--uitest-restore-cached-sync-owner-subject")
        uiTestRestoresCachedSyncOwnerSubject = uiTestRestoreSubjectIndex.flatMap { index -> String? in
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
            #if DEBUG
            try UITestFixtureSeeder.seedFixtures(
                from: arguments,
                ownerTokenIdentifier: uiTestSyncOwner,
                context: container.mainContext
            )
            #endif
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
                if let uiTestSyncOwner {
                    syncScheduler.currentOwnerTokenIdentifier = uiTestSyncOwner
                    if ProcessInfo.processInfo.arguments.contains("--uitest-show-sync-failure") {
                        syncScheduler.recordFailureForTesting(
                            message: "Convex function sync:fetchChanges failed for token \(uiTestSyncOwner)"
                        )
                    }
                    return
                }
                if uiTestRestoresCachedSyncOwner {
                    syncScheduler.configure(modelContext: modelContainer.mainContext)
                    if let uiTestRestoresCachedSyncOwnerSubject {
                        _ = syncScheduler.restoreLastKnownOwnerTokenIdentifier(
                            matchingOwnerSubject: uiTestRestoresCachedSyncOwnerSubject
                        )
                    }
                    return
                }
                if uiTestForcesSignedOutAuth {
                    syncScheduler.configure(modelContext: modelContainer.mainContext)
                    syncScheduler.enterSignedOutMode()
                    return
                }
                configureSyncIfNeeded()
            }
            .onChange(of: scenePhase) { _, newScenePhase in
                guard newScenePhase == .active else { return }
                syncScheduler.requestSyncOnAppForeground()
            }
        }
    }

    private func configureSyncIfNeeded() {
        guard syncAuthTask == nil else { return }

        let syncClient = ConvexSyncClient(client: convexClient)
        let coordinator = SyncCoordinator(client: syncClient)
        syncScheduler.configure(coordinator: coordinator, modelContext: modelContainer.mainContext)

        syncAuthTask = Task { @MainActor in
            let restoredSessionTask = Task { @MainActor in
                await syncConvexAuthFromRestoredClerkSessionIfAvailable()
            }
            defer { restoredSessionTask.cancel() }

            for await state in convexClient.authState.values {
                switch state {
                case .loading:
                    break
                case .unauthenticated:
                    if await restoreCachedSyncOwnerForActiveClerkSessionIfAvailable() {
                        break
                    }
                    syncScheduler.enterSignedOutMode()
                case .authenticated(let token):
                    guard let ownerTokenIdentifier = ClerkJWTIdentityResolver.ownerTokenIdentifier(from: token) else {
                        break
                    }
                    authenticateSyncOwner(ownerTokenIdentifier)
                }
            }
        }
    }

    private func syncConvexAuthFromRestoredClerkSessionIfAvailable() async {
        await waitUntilClerkIsLoaded()
        guard !Task.isCancelled else { return }
        guard Clerk.shared.session?.status == .active else { return }
        activateOwnerForActiveClerkUserOrHideOwnerScopedData()

        let result = await convexClient.loginFromCache()
        let token: String
        switch result {
        case .success(let authToken):
            token = authToken
        case .failure:
            return
        }

        guard let ownerTokenIdentifier = ClerkJWTIdentityResolver.ownerTokenIdentifier(from: token) else {
            return
        }
        authenticateSyncOwner(ownerTokenIdentifier)
    }

    private func restoreCachedSyncOwnerForActiveClerkSessionIfAvailable() async -> Bool {
        await waitUntilClerkIsLoaded()
        guard !Task.isCancelled else { return true }
        guard Clerk.shared.session?.status == .active else { return false }

        activateOwnerForActiveClerkUserOrHideOwnerScopedData()
        return true
    }

    @discardableResult
    private func activateOwnerForActiveClerkUserOrHideOwnerScopedData() -> Bool {
        if let activeClerkOwnerTokenIdentifier {
            if syncScheduler.activateValidatedOwnerTokenIdentifier(activeClerkOwnerTokenIdentifier) {
                return true
            }

            syncScheduler.currentOwnerTokenIdentifier = nil
            return false
        }

        guard let expectedClerkOwnerTokenIdentifier else {
            syncScheduler.currentOwnerTokenIdentifier = nil
            return false
        }

        if !syncScheduler.activateValidatedOwnerTokenIdentifier(expectedClerkOwnerTokenIdentifier) {
            syncScheduler.currentOwnerTokenIdentifier = nil
            return false
        }

        return true
    }

    private var activeClerkUserID: String? {
        Clerk.shared.user?.id ?? Clerk.shared.session?.publicUserData?.userId
    }

    private var expectedClerkOwnerTokenIdentifier: String? {
        guard let activeClerkUserID,
              let expectedClerkIssuer = ClerkJWTIdentityResolver.issuer(
                  fromPublishableKey: ClerkConfiguration.publishableKey
              ) else {
            return nil
        }

        return "\(expectedClerkIssuer)|\(activeClerkUserID)"
    }

    private var activeClerkOwnerTokenIdentifier: String? {
        guard let jwt = Clerk.shared.session?.lastActiveToken?.jwt else {
            return nil
        }

        return ClerkJWTIdentityResolver.ownerTokenIdentifier(from: jwt)
    }

    private func waitUntilClerkIsLoaded() async {
        while !Task.isCancelled {
            if Clerk.shared.isLoaded {
                return
            }

            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func authenticateSyncOwner(_ ownerTokenIdentifier: String) {
        syncScheduler.currentOwnerTokenIdentifier = ownerTokenIdentifier
        syncScheduler.seedDefaultsForCurrentOwner()
        syncScheduler.requestSync()
    }
}
