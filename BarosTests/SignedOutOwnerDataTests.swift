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

        XCTAssertNil(SignedOutOwnerData.find(in: context))
    }

    func testCountsOnlyOwnerScopedCompletedWorkoutsThatAreNotDeleted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
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
            SignedOutOwnerData.find(in: context),
            SignedOutOwnerData(completedWorkoutCount: 2)
        )
    }

    func testOwnerScopedDataWithoutWorkoutsStillMarksReturningUser() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: owner)

        XCTAssertEqual(
            SignedOutOwnerData.find(in: context),
            SignedOutOwnerData(completedWorkoutCount: 0)
        )
    }

    func testLocalDataResetLeavesNoSignedOutOwnerData() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: owner)
        context.insert(makeCompletedSession(owner: owner))
        try context.save()

        try LocalDataResetService().reset(context: context)

        XCTAssertNil(SignedOutOwnerData.find(in: context))
    }

    func testSignInMessageReflectsWorkoutCount() {
        XCTAssertEqual(
            SignedOutOwnerData(completedWorkoutCount: 0).signInMessage,
            "Sign in to see the workouts saved to your account."
        )
        XCTAssertEqual(
            SignedOutOwnerData(completedWorkoutCount: 1).signInMessage,
            "Your workout is safe. Sign in to see it again."
        )
        XCTAssertEqual(
            SignedOutOwnerData(completedWorkoutCount: 42).signInMessage,
            "Your 42 workouts are safe. Sign in to see them again."
        )
    }

    func testBannerOnlyShowsForUndismissedSignedOutOwnerWhileLocalOnly() {
        let data = SignedOutOwnerData(completedWorkoutCount: 5)

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
        XCTAssertEqual(scheduler.signedOutOwnerData, SignedOutOwnerData(completedWorkoutCount: 1))
    }

    func testSignInClearsSignedOutOwnerDataAndDismissal() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(makeCompletedSession(owner: owner))
        try context.save()
        let dismissalStore = makeDismissalStore()
        let scheduler = makeScheduler(context: context, dismissalStore: dismissalStore)
        scheduler.enterSignedOutMode()
        scheduler.dismissSignedOutReminder()
        XCTAssertTrue(scheduler.isSignedOutReminderDismissed)
        XCTAssertTrue(dismissalStore.isDismissed)

        XCTAssertTrue(scheduler.activateValidatedOwnerTokenIdentifier(owner))

        XCTAssertNil(scheduler.signedOutOwnerData)
        XCTAssertFalse(scheduler.isSignedOutReminderDismissed)
        XCTAssertFalse(dismissalStore.isDismissed)
    }

    func testDismissalPersistsAcrossLaunchesWhileStillSignedOut() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let dismissalStore = makeDismissalStore()
        makeScheduler(context: context, dismissalStore: dismissalStore).dismissSignedOutReminder()

        let relaunchedScheduler = makeScheduler(context: context, dismissalStore: dismissalStore)
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
        dismissalStore: SignedOutReminderDismissalStore? = nil
    ) -> SyncScheduler {
        SyncScheduler(
            modelContext: context,
            lastKnownOwnerTokenStore: LastKnownSyncOwnerTokenStore(userDefaults: makeDefaults()),
            signedOutReminderDismissalStore: dismissalStore ?? makeDismissalStore()
        )
    }

    private func makeDismissalStore() -> SignedOutReminderDismissalStore {
        SignedOutReminderDismissalStore(userDefaults: makeDefaults())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SignedOutOwnerDataTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
