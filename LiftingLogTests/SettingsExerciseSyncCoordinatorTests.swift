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

    func testRunPushesSettingsAndExerciseEntriesThenRemovesOutbox() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let settings = UserSettings(id: UUID(uuidString: "00000000-0000-0000-0000-000000003001")!)
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003002")!,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest"
        )
        context.insert(settings)
        context.insert(exercise)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .userSettings, entityID: settings.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try recorder.recordCreate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedSettings.count, 1)
        XCTAssertEqual(client.upsertedSettings.first?.clientId, settings.id.uuidString.lowercased())
        XCTAssertEqual(client.upsertedExercises.count, 1)
        XCTAssertEqual(client.upsertedExercises.first?.clientId, exercise.id.uuidString.lowercased())
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunMarksFailedEntryAndStopsOnPushError() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003003")!,
            name: "Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.error = PushError()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.lastErrorMessage, "offline")
    }

    func testRunRetriesPreviouslyFailedEntryOnNextRun() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003004")!,
            name: "Deadlift",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Hamstrings"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_a"
        context.insert(exercise)
        let entry = SyncOutboxEntry(
            entityKind: .exercise,
            entityID: exercise.id,
            operation: .update,
            status: .failed,
            ownerTokenIdentifier: "issuer|owner_a",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        entry.lastErrorMessage = "offline"
        context.insert(entry)
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedExercises.map { $0.clientId }, [exercise.id.uuidString.lowercased()])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunDoesNotPushModelOwnedByDifferentOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003005")!,
            name: "Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Shoulders"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_b"
        context.insert(exercise)
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.upsertedExercises.count, 0)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.lastErrorMessage, "Cannot sync exercise \(exercise.id.uuidString) because the local record belongs to a different owner.")
    }

    func testRunTombstonesMissingExerciseForUpdateEntry() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000003006")!
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(client.tombstones.count, 1)
        XCTAssertEqual(client.tombstones.first?.0, .exercise)
        XCTAssertEqual(client.tombstones.first?.1, exerciseID)
        XCTAssertEqual(client.tombstones.first?.2, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunRetriesMissingExerciseTombstoneWithOriginalTimestamp() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000003010")!
        try SyncOutboxRecorder().recordUpdate(entityKind: .exercise, entityID: exerciseID, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try context.save()

        let firstClient = FakeSettingsExerciseSyncClient()
        firstClient.error = PushError()
        let coordinator = SettingsExerciseSyncCoordinator(client: firstClient)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let failedEntry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(failedEntry.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertNotEqual(failedEntry.updatedAt, Date(timeIntervalSince1970: 100))

        let retryClient = FakeSettingsExerciseSyncClient()
        try await SettingsExerciseSyncCoordinator(client: retryClient).run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertEqual(retryClient.tombstones.count, 1)
        XCTAssertEqual(retryClient.tombstones.first?.0, .exercise)
        XCTAssertEqual(retryClient.tombstones.first?.1, exerciseID)
        XCTAssertEqual(retryClient.tombstones.first?.2, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
    }

    func testRunDoesNotTombstoneModelOwnedByDifferentOwner() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003009")!,
            name: "Other Owner Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )
        exercise.syncOwnerTokenIdentifier = "issuer|owner_b"
        exercise.markDeleted(now: Date(timeIntervalSince1970: 120))
        context.insert(exercise)
        try SyncOutboxRecorder().recordDelete(entityKind: .exercise, entityID: exercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 130))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        XCTAssertTrue(client.tombstones.isEmpty)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOutboxEntry>()).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.lastErrorMessage, "Cannot sync exercise \(exercise.id.uuidString) because the local record belongs to a different owner.")
    }

    func testRunLeavesSecondPendingEntryPendingAfterFirstEntryFailure() async throws {
        struct PushError: LocalizedError { var errorDescription: String? { "offline" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let failedExercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003007")!,
            name: "Curl",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscle: "Biceps"
        )
        let pendingExercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003008")!,
            name: "Row",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscle: "Back"
        )
        context.insert(failedExercise)
        context.insert(pendingExercise)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .exercise, entityID: failedExercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 100))
        try recorder.recordUpdate(entityKind: .exercise, entityID: pendingExercise.id, ownerTokenIdentifier: "issuer|owner_a", context: context, now: Date(timeIntervalSince1970: 200))
        try context.save()

        let client = FakeSettingsExerciseSyncClient()
        client.error = PushError()
        let coordinator = SettingsExerciseSyncCoordinator(client: client)
        try await coordinator.run(ownerTokenIdentifier: "issuer|owner_a", context: context)

        let entries = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        let failedEntry = try XCTUnwrap(entries.first { $0.entityID == failedExercise.id })
        let pendingEntry = try XCTUnwrap(entries.first { $0.entityID == pendingExercise.id })
        XCTAssertEqual(failedEntry.status, .failed)
        XCTAssertEqual(pendingEntry.status, .pending)
    }
}

final class FakeSettingsExerciseSyncClient: SettingsExerciseSyncClient, @unchecked Sendable {
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
