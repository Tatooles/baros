import Foundation
import SwiftData
import XCTest
@testable import BarosCore

/// One test per reported bug, written against APIs that predate the fix, so
/// each one fails on the code before it and passes after.
@MainActor
final class SyncConvergenceRegressionTests: XCTestCase {
    private let owner = "issuer|owner_a"

    /// #97: a workout deleted here and edited elsewhere stayed deleted here and
    /// alive everywhere else, because the pull kept the local delete without
    /// ever sending it again.
    func testPullSendsALocalDeleteAgainWhenTheServerHoldsALiveCopy() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000a701")!,
            name: "Deleted Here",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner,
            updatedAt: Date(timeIntervalSince1970: 20),
            deletedAt: Date(timeIntervalSince1970: 20)
        )
        context.insert(exercise)
        try markBootstrapped(context)

        // The first run after updating sends the delete once, and it completes.
        try await SyncCoordinator(client: FakeSyncClient()).run(ownerTokenIdentifier: owner, context: context)

        // Later an older device revives the record on the server.
        let client = FakeSyncClient()
        client.fetchResponses = [
            exerciseResponse([exerciseRecord(id: exercise.id, name: "Edited Elsewhere", updatedAt: 40, serverUpdatedAt: 45)], cursor: 45),
        ]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertNotNil(exercise.deletedAt)
        XCTAssertEqual(exercise.name, "Deleted Here")
        XCTAssertEqual(client.tombstones.map(\.1), [exercise.id], "The delete is sent again so the server applies it.")
    }

    /// #98: a device whose clock ran ahead stamped its copy in the future, and
    /// then refused every later server version stamped below it.
    func testIdleDeviceAdoptsTheServersVersionEvenWhenItsOwnStampIsLater() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000a801")!,
            name: "Stamped By A Fast Clock",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            syncOwnerTokenIdentifier: owner,
            updatedAt: Date(timeIntervalSince1970: 4_000_000_000)
        )
        context.insert(exercise)
        try markBootstrapped(context)

        let client = FakeSyncClient()
        client.fetchResponses = [
            exerciseResponse([exerciseRecord(id: exercise.id, name: "Server Version", updatedAt: 1_800_000_000, serverUpdatedAt: 50)], cursor: 50),
        ]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(exercise.name, "Server Version")
        XCTAssertEqual(exercise.updatedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// #98: after pulling a version stamped by a fast clock, an edit made on an
    /// honest clock was stamped below it and lost to it on every device.
    func testAnEditAfterPullingAFastClockVersionIsStampedAboveIt() async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try markBootstrapped(context)
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000a802")!
        let fastStamp: Double = 4_000_000_000
        let client = FakeSyncClient()
        client.fetchResponses = [
            exerciseResponse([exerciseRecord(id: id, name: "From A Fast Clock", updatedAt: fastStamp, serverUpdatedAt: 60)], cursor: 60),
        ]
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.id == id })

        exercise.name = "Edited On An Honest Clock"
        exercise.touch(now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertGreaterThan(exercise.updatedAt.timeIntervalSince1970, fastStamp)
    }

    /// #96: one record the server rejected stopped every later upload, forever.
    func testOneRejectedRecordDoesNotHoldBackTheRestOfTheQueue() async throws {
        struct Rejection: LocalizedError { var errorDescription: String? { "invalid payload" } }
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let poison = Exercise(name: "Poison", category: .strength, equipment: .barbell, primaryMuscle: "Chest", syncOwnerTokenIdentifier: owner)
        let healthy = Exercise(name: "Healthy", category: .strength, equipment: .barbell, primaryMuscle: "Back", syncOwnerTokenIdentifier: owner)
        context.insert(poison)
        context.insert(healthy)
        let recorder = SyncOutboxRecorder()
        try recorder.recordUpdate(entityKind: .exercise, entityID: poison.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 100))
        try recorder.recordUpdate(entityKind: .exercise, entityID: healthy.id, ownerTokenIdentifier: owner, context: context, now: Date(timeIntervalSince1970: 200))
        try markBootstrapped(context)

        let client = FakeSyncClient()
        let poisonID = poison.id.uuidString.lowercased()
        client.onUpsertExercise = { record in
            if record.clientId == poisonID { throw Rejection() }
        }
        try await SyncCoordinator(client: client).run(ownerTokenIdentifier: owner, context: context)

        XCTAssertEqual(client.upsertedExercises.map(\.clientId), [healthy.id.uuidString.lowercased()])
        let remaining = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(remaining.map(\.entityID), [poison.id])
    }

    // MARK: Helpers

    private func markBootstrapped(_ context: ModelContext) throws {
        let state = try SyncCursorState.state(for: owner, context: context)
        state.hasBootstrappedSettingsExercises = true
        state.hasBootstrappedWorkoutGraph = true
        try context.save()
    }
}

func exerciseRecord(
    id: UUID,
    name: String,
    updatedAt: Double,
    deletedAt: Double? = nil,
    serverUpdatedAt: Double,
    createdAt: Double = 10
) -> ExerciseSyncRecord {
    ExerciseSyncRecord(
        clientId: id.uuidString.lowercased(),
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        serverUpdatedAt: serverUpdatedAt,
        seedIdentifier: nil,
        name: name,
        categoryRaw: "strength",
        equipmentRaw: "barbell",
        primaryMuscleRaw: "Chest",
        primaryMuscleGroupRaw: "chest",
        notes: "",
        isArchived: false,
        isSeeded: false
    )
}

func exerciseResponse(_ exercises: [ExerciseSyncRecord], cursor: Double) -> SyncFetchChangesResponse {
    SyncFetchChangesResponse(
        userSettings: [],
        exercises: exercises,
        workoutSessions: [],
        loggedExercises: [],
        loggedSets: [],
        cursors: SyncChangeCursors(userSettings: 0, exercises: cursor),
        hasMore: SyncHasMore(userSettings: false, exercises: false)
    )
}
