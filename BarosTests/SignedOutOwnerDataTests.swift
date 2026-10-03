import SwiftData
import XCTest
@testable import Baros

@MainActor
final class SignedOutOwnerDataTests: XCTestCase {
    private let owner = "issuer|owner_a"

    func testFirstTimeDeviceWithOnlyOwnerlessDataHasNoSignedOutOwnerData() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)
        context.insert(makeCompletedSession(owner: nil))
        try context.save()

        XCTAssertNil(find(in: context, preferredOwners: [nil]))
    }

    func testCountsOnlyTheSignedOutOwnersCompletedWorkoutsThatAreNotDeleted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: owner))
        context.insert(makeCompletedSession(owner: owner))
        context.insert(makeCompletedSession(owner: "issuer|owner_b"))
        context.insert(makeCompletedSession(owner: owner, deletedAt: .now))
        context.insert(makeCompletedSession(owner: nil))
        context.insert(WorkoutSession(
            title: "Unfinished",
            startedAt: .now,
            status: .active,
            source: .blank,
            syncOwnerTokenIdentifier: owner
        ))
        try context.save()

        XCTAssertEqual(
            find(in: context, preferredOwners: [owner]),
            SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 2)
        )
    }

    func testSkipsPreferredOwnersWithoutLocalDataAndInfersTheOnlyLocalOwner() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: owner))
        try context.save()

        XCTAssertEqual(
            find(in: context, preferredOwners: [nil, "issuer|stale_owner"]),
            SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 1)
        )
    }

    func testUnknownOwnerAmongSeveralLocalOwnersShowsNoCount() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: owner))
        context.insert(makeCompletedSession(owner: "issuer|owner_b"))
        try context.save()

        XCTAssertEqual(
            find(in: context, preferredOwners: [nil]),
            SignedOutOwnerData(ownerTokenIdentifier: nil, completedWorkoutCount: 0)
        )
    }

    func testOwnerScopedDataWithoutWorkoutsStillMarksReturningUser() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: owner)

        XCTAssertEqual(
            find(in: context, preferredOwners: [owner]),
            SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 0)
        )
    }

    func testLocalDataResetLeavesNoSignedOutOwnerData() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: owner)
        context.insert(makeCompletedSession(owner: owner))
        try context.save()

        try LocalDataResetService().reset(context: context)

        XCTAssertNil(find(in: context, preferredOwners: [owner]))
    }

    func testSignInMessageReflectsWorkoutCount() {
        XCTAssertEqual(
            SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 0).signInMessage,
            "Sign in to see the workouts saved to your account."
        )
        XCTAssertEqual(
            SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 1).signInMessage,
            "Your workout is safe. Sign in to see it again."
        )
        XCTAssertEqual(
            SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 42).signInMessage,
            "Your 42 workouts are safe. Sign in to see them again."
        )
    }

    func testBannerOnlyShowsForUndismissedSignedOutOwnerWhileLocalOnly() {
        let data = SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 5)

        XCTAssertEqual(
            SignedOutReminderPresentation.bannerData(
                currentOwnerState: .localOnly,
                signedOutOwnerData: data,
                isDismissed: false
            ),
            data
        )
        XCTAssertNil(SignedOutReminderPresentation.bannerData(
            currentOwnerState: .localOnly,
            signedOutOwnerData: data,
            isDismissed: true
        ))
        XCTAssertNil(SignedOutReminderPresentation.bannerData(
            currentOwnerState: .localOnly,
            signedOutOwnerData: nil,
            isDismissed: false
        ))
        XCTAssertNil(SignedOutReminderPresentation.bannerData(
            currentOwnerState: .resolving(ownerTokenIdentifier: owner),
            signedOutOwnerData: data,
            isDismissed: false
        ))
        XCTAssertNil(SignedOutReminderPresentation.bannerData(
            currentOwnerState: .active(ownerTokenIdentifier: owner),
            signedOutOwnerData: data,
            isDismissed: false
        ))
    }

    func testSchedulerFindsSignedOutOwnerDataWhenEnteringSignedOutMode() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: owner))
        try context.save()
        let scheduler = makeScheduler(context: context)
        scheduler.currentOwnerTokenIdentifier = owner

        scheduler.enterSignedOutMode()

        XCTAssertNil(scheduler.currentOwnerTokenIdentifier)
        XCTAssertEqual(scheduler.signedOutOwnerData, SignedOutOwnerData(ownerTokenIdentifier: owner, completedWorkoutCount: 1))
    }

    func testSchedulerKeepsCountScopedToSignedOutOwnerAcrossLaterChecks() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: "issuer|owner_a"))
        context.insert(makeCompletedSession(owner: "issuer|owner_a"))
        context.insert(makeCompletedSession(owner: "issuer|owner_b"))
        try context.save()
        let reminderStore = makeReminderStore()
        let scheduler = makeScheduler(context: context, reminderStore: reminderStore)
        scheduler.currentOwnerTokenIdentifier = "issuer|owner_b"

        scheduler.enterSignedOutMode()
        // A foreground check or relaunch runs again after the last-known owner was cleared.
        let relaunchedScheduler = makeScheduler(context: context, reminderStore: reminderStore)
        relaunchedScheduler.enterSignedOutMode()

        let expected = SignedOutOwnerData(ownerTokenIdentifier: "issuer|owner_b", completedWorkoutCount: 1)
        XCTAssertEqual(scheduler.signedOutOwnerData, expected)
        XCTAssertEqual(relaunchedScheduler.signedOutOwnerData, expected)
    }

    func testSignInClearsSignedOutOwnerDataAndDismissal() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: owner))
        try context.save()
        let reminderStore = makeReminderStore()
        let scheduler = makeScheduler(context: context, reminderStore: reminderStore)
        scheduler.enterSignedOutMode()
        scheduler.dismissSignedOutReminder()
        XCTAssertTrue(scheduler.isSignedOutReminderDismissed)
        XCTAssertTrue(reminderStore.isDismissed)

        XCTAssertTrue(scheduler.activateValidatedOwnerTokenIdentifier(owner))

        XCTAssertNil(scheduler.signedOutOwnerData)
        XCTAssertFalse(scheduler.isSignedOutReminderDismissed)
        XCTAssertFalse(reminderStore.isDismissed)
    }

    func testDismissalPersistsAcrossLaunchesWhileStillSignedOut() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let reminderStore = makeReminderStore()
        makeScheduler(context: context, reminderStore: reminderStore).dismissSignedOutReminder()

        let relaunchedScheduler = makeScheduler(context: context, reminderStore: reminderStore)
        relaunchedScheduler.enterSignedOutMode()

        XCTAssertTrue(relaunchedScheduler.isSignedOutReminderDismissed)
    }

    func testDataDeletionClearsSignedOutOwnerData() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: owner))
        try context.save()
        let scheduler = makeScheduler(context: context)
        scheduler.enterSignedOutMode()
        XCTAssertNotNil(scheduler.signedOutOwnerData)

        scheduler.resetAfterDataDeletion()

        XCTAssertNil(scheduler.signedOutOwnerData)
    }

    private func makeCompletedSession(owner: String?, deletedAt: Date? = nil) -> WorkoutSession {
        WorkoutSession(
            title: "Push",
            startedAt: .now,
            endedAt: .now,
            status: .completed,
            source: .blank,
            deletedAt: deletedAt,
            syncOwnerTokenIdentifier: owner
        )
    }

    private func makeScheduler(
        context: ModelContext,
        reminderStore: SignedOutReminderStore? = nil
    ) -> SyncScheduler {
        SyncScheduler(
            modelContext: context,
            lastKnownOwnerTokenStore: LastKnownSyncOwnerTokenStore(userDefaults: makeDefaults()),
            signedOutReminderStore: reminderStore ?? makeReminderStore()
        )
    }

    private func makeReminderStore() -> SignedOutReminderStore {
        SignedOutReminderStore(userDefaults: makeDefaults())
    }

    private func find(in context: ModelContext, preferredOwners: [String?]) -> SignedOutOwnerData? {
        SignedOutOwnerData.find(
            in: context,
            preferredOwnerTokenIdentifiers: preferredOwners,
            localOwnerTokenIdentifiers: { Self.localOwners(in: context) }
        )
    }

    private static func localOwners(in context: ModelContext) -> Set<String> {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return Set(sessions.compactMap(\.syncOwnerTokenIdentifier))
            .union(exercises.compactMap(\.syncOwnerTokenIdentifier))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SignedOutOwnerDataTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
