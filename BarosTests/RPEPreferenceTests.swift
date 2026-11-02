import SwiftData
import XCTest
@testable import Baros

@MainActor
final class RPEPreferenceTests: XCTestCase {
    private let suiteName = "RPEPreferenceTests"
    private let owner = "issuer|owner_a"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    override func setUp() async throws {
        try await super.setUp()
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private var storedChoice: Bool? {
        defaults.object(forKey: RPEPreference.storageKey) as? Bool
    }

    func testExistingRatingTurnsOnAndTheCheckNeverRunsAgain() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(LoggedSet(orderIndex: 0, rpe: 8))

        RPEPreference.checkExistingRatingsOnce(context: context, defaults: defaults)
        XCTAssertEqual(storedChoice, true)

        defaults.removeObject(forKey: RPEPreference.storageKey)
        RPEPreference.checkExistingRatingsOnce(context: context, defaults: defaults)
        XCTAssertNil(storedChoice)
    }

    func testNoRatingsLeavesItUndecidedSoSyncCanStillTurnItOn() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let deleted = LoggedSet(orderIndex: 0, rpe: 8)
        deleted.deletedAt = .now
        context.insert(deleted)
        context.insert(LoggedSet(orderIndex: 1))

        RPEPreference.checkExistingRatingsOnce(context: context, defaults: defaults)
        XCTAssertNil(storedChoice)

        RPEPreference.enableIfUndecided(defaults: defaults)
        XCTAssertEqual(storedChoice, true)
    }

    func testExistingRatingDoesNotOverrideAChoice() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(LoggedSet(orderIndex: 0, rpe: 8))
        defaults.set(false, forKey: RPEPreference.storageKey)

        RPEPreference.checkExistingRatingsOnce(context: context, defaults: defaults)
        XCTAssertEqual(storedChoice, false)
    }

    func testPullingARatedSetTurnsOnWhenUndecided() async throws {
        try await pullSet(rpe: 8)
        XCTAssertEqual(storedChoice, true)
    }

    func testPullingARatedSetDoesNotOverrideAChoice() async throws {
        defaults.set(false, forKey: RPEPreference.storageKey)
        try await pullSet(rpe: 8)
        XCTAssertEqual(storedChoice, false)
    }

    func testPullingUnratedOrDeletedSetsLeavesItUndecided() async throws {
        try await pullSet(rpe: nil)
        XCTAssertNil(storedChoice)
        try await pullSet(rpe: 8, deletedAt: 40)
        XCTAssertNil(storedChoice)
    }

    private func pullSet(rpe: Double?, deletedAt: Double? = nil) async throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let loggedExercise = LoggedExercise(orderIndex: 0)
        let session = WorkoutSession(
            title: "Push", startedAt: .now, status: .completed, source: .blank, loggedExercises: [loggedExercise]
        )
        session.syncOwnerTokenIdentifier = owner
        loggedExercise.session = session
        context.insert(session)
        try context.save()

        let client = FakeSyncClient()
        client.fetchResponses = [
            SyncFetchChangesResponse(
                userSettings: [],
                exercises: [],
                workoutSessions: [],
                loggedExercises: [],
                loggedSets: [
                    LoggedSetSyncRecord(
                        clientId: UUID().uuidString.lowercased(),
                        createdAt: 13,
                        updatedAt: 23,
                        deletedAt: deletedAt,
                        serverUpdatedAt: 33,
                        loggedExerciseClientId: loggedExercise.id.uuidString.lowercased(),
                        orderIndex: 0,
                        weight: 185,
                        reps: 5,
                        rpe: rpe,
                        kindRaw: "working",
                        isCompleted: true,
                        completedAt: 190,
                        notes: "",
                        healthLinkID: nil,
                        sourceLoggedSetID: nil
                    )
                ],
                cursors: SyncChangeCursors(
                    userSettings: 0,
                    exercises: 0,
                    workoutSessions: 0,
                    loggedExercises: 0,
                    loggedSets: 33
                ),
                hasMore: SyncHasMore(userSettings: false, exercises: false)
            )
        ]

        try await SyncCoordinator(client: client, rpeDefaults: defaults)
            .run(ownerTokenIdentifier: owner, context: context)
    }
}
