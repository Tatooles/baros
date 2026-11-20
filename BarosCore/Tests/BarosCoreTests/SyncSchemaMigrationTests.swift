import Foundation
import SwiftData
import XCTest
@testable import BarosCore

/// The sync models as installed builds store them, before rejection counts,
/// dead-lettering, sync bases and the one-time update step.
private enum InstalledSyncSchema {
    /// One record model, to check `syncBaseUpdatedAt` migrates over existing rows.
    @Model
    final class UserSettings {
        @Attribute(.unique) var id: UUID
        var weightUnitRaw: String
        var defaultRestTimerSeconds: Int
        var hasCompletedOnboarding: Bool
        var syncOwnerTokenIdentifier: String?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?

        init(id: UUID) {
            self.id = id
            weightUnitRaw = "kilograms"
            defaultRestTimerSeconds = 120
            hasCompletedOnboarding = true
            syncOwnerTokenIdentifier = "issuer|owner_a"
            createdAt = Date(timeIntervalSince1970: 10)
            updatedAt = Date(timeIntervalSince1970: 20)
        }
    }

    @Model
    final class SyncOutboxEntry {
        @Attribute(.unique) var id: UUID
        var entityKindRaw: String
        var entityID: UUID
        var operationRaw: String
        var statusRaw: String
        var ownerTokenIdentifier: String?
        var createdAt: Date
        var updatedAt: Date
        var lastAttemptAt: Date?
        var attemptCount: Int
        var lastErrorMessage: String?

        init(id: UUID, entityKindRaw: String, entityID: UUID, operationRaw: String, statusRaw: String,
             ownerTokenIdentifier: String?, createdAt: Date, updatedAt: Date, attemptCount: Int) {
            self.id = id
            self.entityKindRaw = entityKindRaw
            self.entityID = entityID
            self.operationRaw = operationRaw
            self.statusRaw = statusRaw
            self.ownerTokenIdentifier = ownerTokenIdentifier
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.attemptCount = attemptCount
        }
    }

    @Model
    final class SyncCursorState {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var ownerTokenIdentifier: String
        var userSettingsCursor: Double
        var exercisesCursor: Double
        var workoutSessionsCursor: Double = 0
        var loggedExercisesCursor: Double = 0
        var loggedSetsCursor: Double = 0
        var workoutTemplatesCursor: Double = 0
        var hasBootstrappedSettingsExercises: Bool = false
        var hasBootstrappedWorkoutGraph: Bool = false

        init(ownerTokenIdentifier: String) {
            id = UUID()
            self.ownerTokenIdentifier = ownerTokenIdentifier
            userSettingsCursor = 12
            exercisesCursor = 34
            hasBootstrappedSettingsExercises = true
            hasBootstrappedWorkoutGraph = true
        }
    }
}

/// The fields this change adds must open an installed build's store with
/// SwiftData's lightweight migration, keeping every row.
@MainActor
final class SyncSchemaMigrationTests: XCTestCase {
    func testInstalledStoreOpensWithTheNewSyncFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("installed.store")
        let entryID = UUID()
        let exerciseID = UUID()
        let settingsID = UUID()

        do {
            let installed = try ModelContainer(
                for: Schema([
                    InstalledSyncSchema.SyncOutboxEntry.self,
                    InstalledSyncSchema.SyncCursorState.self,
                    InstalledSyncSchema.UserSettings.self,
                ]),
                configurations: ModelConfiguration(url: url)
            )
            let context = installed.mainContext
            context.insert(InstalledSyncSchema.SyncOutboxEntry(
                id: entryID, entityKindRaw: "exercises", entityID: exerciseID, operationRaw: "update",
                statusRaw: "failed", ownerTokenIdentifier: "issuer|owner_a",
                createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200),
                attemptCount: 41_000
            ))
            context.insert(InstalledSyncSchema.SyncCursorState(ownerTokenIdentifier: "issuer|owner_a"))
            context.insert(InstalledSyncSchema.UserSettings(id: settingsID))
            try context.save()
        }

        let updated = try ModelContainer(for: Schema(BarosSchema.models), configurations: ModelConfiguration(url: url))
        let context = updated.mainContext
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.id, entryID)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.attemptCount, 41_000)
        XCTAssertEqual(entry.rejectionCount, 0, "Old stuck entries start with no rejections counted.")
        XCTAssertNil(entry.nextAttemptAt)
        XCTAssertNil(entry.firstRejectedAt)

        let state = try XCTUnwrap(context.fetch(FetchDescriptor<SyncCursorState>()).first)
        XCTAssertEqual(state.exercisesCursor, 34)
        XCTAssertTrue(state.hasBootstrappedWorkoutGraph)
        XCTAssertFalse(state.hasRunConvergenceUpgrade, "The one-time update step still runs.")

        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(settings.id, settingsID)
        XCTAssertEqual(settings.weightUnitRaw, "kilograms")
        XCTAssertNil(settings.syncBaseUpdatedAt)
    }
}
