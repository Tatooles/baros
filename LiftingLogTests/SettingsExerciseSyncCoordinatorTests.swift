import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class SettingsExerciseSyncCoordinatorTests: XCTestCase {
    func testFirstRunClaimsUnownedSettingsExercisesAndOutboxEntries() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(id: UUID(uuidString: "00000000-0000-0000-0000-000000002001")!)
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002002")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(settings)
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(
            entityKind: .userSettings,
            entityID: settings.id,
            ownerTokenIdentifier: nil,
            context: context,
            now: Date(timeIntervalSince1970: 100)
        )
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(settings.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(entries.first?.ownerTokenIdentifier, "issuer|owner_a")
    }

    func testPrepareSkipsRowsOwnedByDifferentOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(exercise)
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_b", context: context)

        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
    }

    func testPrepareReturnsRelevantInFlightEntriesToPending() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let entry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000002003")!,
            operation: .update,
            status: .inFlight,
            ownerTokenIdentifier: "issuer|owner_a",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(entry)
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(entry.status, .pending)
    }

    func testPrepareDoesNotClaimNilOwnerOutboxEntryForRecordOwnedByDifferentOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002004")!,
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(exercise)
        let entry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: exercise.id,
            operation: .update,
            ownerTokenIdentifier: nil,
            now: Date(timeIntervalSince1970: 100)
        )
        context.insert(entry)
        try context.save()

        let coordinator = SettingsExerciseSyncCoordinator(client: FakeSettingsExerciseSyncClient())
        try coordinator.prepareForSync(ownerTokenIdentifier: "issuer|owner_b", context: context)

        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertNil(entry.ownerTokenIdentifier)
    }
}

final class FakeSettingsExerciseSyncClient: SettingsExerciseSyncClient {
    var upsertedSettings: [UserSettingsSyncPayload] = []
    var upsertedExercises: [ExerciseSyncPayload] = []
    var tombstones: [(SyncEntityKind, UUID, Date)] = []
    var fetchResponse = SyncFetchChangesResponse(
        userSettings: [],
        exercises: [],
        cursors: SyncChangeCursors(userSettings: 0, exercises: 0),
        hasMore: SyncHasMore(userSettings: false, exercises: false)
    )
    var error: Error?

    func upsertUserSettings(_ record: UserSettingsSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        upsertedSettings.append(record)
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func upsertExercise(_ record: ExerciseSyncPayload) async throws -> SyncMutationResult {
        if let error { throw error }
        upsertedExercises.append(record)
        return SyncMutationResult(status: "updated", serverUpdatedAt: 1)
    }

    func tombstone(entityKind: SyncEntityKind, clientId: UUID, deletedAt: Date) async throws -> SyncMutationResult {
        if let error { throw error }
        tombstones.append((entityKind, clientId, deletedAt))
        return SyncMutationResult(status: "tombstoned", serverUpdatedAt: 1)
    }

    func fetchChanges(cursors: SyncChangeCursors, limit: Int) async throws -> SyncFetchChangesResponse {
        if let error { throw error }
        return fetchResponse
    }
}
