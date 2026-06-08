import Foundation
import SwiftData

@MainActor
@Observable
final class SyncScheduler {
    var currentOwnerTokenIdentifier: String?
    private(set) var requestCount = 0
    private var coordinator: SettingsExerciseSyncCoordinator?
    private var modelContext: ModelContext?
    private var syncTask: Task<Void, Never>?
    private var needsSync = false

    init(coordinator: SettingsExerciseSyncCoordinator? = nil, modelContext: ModelContext? = nil) {
        self.coordinator = coordinator
        self.modelContext = modelContext
    }

    func configure(coordinator: SettingsExerciseSyncCoordinator, modelContext: ModelContext) {
        self.coordinator = coordinator
        self.modelContext = modelContext
    }

    func requestSync() {
        requestCount += 1
        guard let coordinator, let modelContext else { return }
        guard syncTask == nil else {
            needsSync = true
            return
        }

        syncTask = Task { @MainActor in
            while true {
                needsSync = false
                try? await coordinator.run(ownerTokenIdentifier: currentOwnerTokenIdentifier, context: modelContext)
                guard needsSync else { break }
            }
            syncTask = nil
        }
    }
}
