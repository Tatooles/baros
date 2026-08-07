import SwiftData
import XCTest
@testable import Baros

/// ADR 0002 makes Unclaimed Local Data outbox-free, so sync preparation is its
/// only route to the cloud. That works only if preparation can adopt such data
/// on *every* run, not just an owner's first one. `adoptUnclaimedLoggedWorkoutsForSync`
/// does that for Logged Workouts; these tests cover the settings and exercise
/// records, whose claim path still requires an outbox entry that no longer exists.
@MainActor
final class SyncUnclaimedAdoptionTests: XCTestCase {
    private let ownerTokenIdentifier = "issuer|owner_a"

    /// Signed out after bootstrap, the user creates a custom Exercise Library
    /// Entry. It carries no outbox intent, and the one-time bootstrap has
    /// already run, so nothing else can enqueue it.
    func testBootstrappedPrepareAdoptsUnclaimedCustomExercise() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(bootstrappedCursorState())
        let exercise = Exercise(
            name: "Zercher Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads",
            isSeeded: false
        )
        context.insert(exercise)
        try context.save()

        try SyncCoordinator(client: FakeSyncClient())
            .prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

        XCTAssertEqual(exercise.syncOwnerTokenIdentifier, ownerTokenIdentifier)
        let entry = try XCTUnwrap(
            outboxEntries(in: context).first { $0.entityID == exercise.id }
        )
        XCTAssertEqual(entry.entityKind, .exercise)
        XCTAssertEqual(entry.ownerTokenIdentifier, ownerTokenIdentifier)
    }

    /// The counterpart guard: signed-out mode re-seeds the default library as
    /// ownerless rows. Adopting those would duplicate the owner's own seeds, so
    /// adoption must stay limited to user-created entries.
    func testBootstrappedPrepareStillDoesNotAdoptUnclaimedSeededExercise() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(bootstrappedCursorState())
        let seeded = Exercise(
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true
        )
        context.insert(seeded)
        try context.save()

        try SyncCoordinator(client: FakeSyncClient())
            .prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

        XCTAssertNil(seeded.syncOwnerTokenIdentifier)
        XCTAssertTrue(outboxEntries(in: context).isEmpty)
    }

    /// Adoption must not reach across accounts: an unclaimed custom entry stays
    /// local while another owner's data is present on the device.
    func testBootstrappedPrepareDoesNotAdoptCustomExerciseWhenAnotherOwnerHasLocalData() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(bootstrappedCursorState())
        context.insert(SyncCursorState(ownerTokenIdentifier: "issuer|owner_b"))
        let exercise = Exercise(
            name: "Zercher Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads",
            isSeeded: false
        )
        context.insert(exercise)
        try context.save()

        try SyncCoordinator(client: FakeSyncClient())
            .prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

        XCTAssertNil(exercise.syncOwnerTokenIdentifier)
        XCTAssertTrue(outboxEntries(in: context).isEmpty)
    }

    /// Diagnostic for the settings singleton: does a signed-out preference edit
    /// made after bootstrap reach the cloud, or is it stranded the same way?
    func testBootstrappedPrepareAdoptsUnclaimedSettings() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(bootstrappedCursorState())
        let settings = UserSettings(defaultRestTimerSeconds: 240)
        context.insert(settings)
        try context.save()

        try SyncCoordinator(client: FakeSyncClient())
            .prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

        XCTAssertEqual(settings.syncOwnerTokenIdentifier, ownerTokenIdentifier)
        let entry = try XCTUnwrap(
            outboxEntries(in: context).first { $0.entityID == settings.id }
        )
        XCTAssertEqual(entry.entityKind, .userSettings)
        XCTAssertEqual(entry.ownerTokenIdentifier, ownerTokenIdentifier)
    }

    /// Owned and ownerless settings coexist as separate rows, so adoption must not
    /// run when the owner already has one: that would either leave the account with
    /// two owned singletons or overwrite its preferences with local mode's.
    func testBootstrappedPrepareDoesNotAdoptUnclaimedSettingsWhenOwnerAlreadyHasSettings() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(bootstrappedCursorState())
        let ownedSettings = UserSettings(
            defaultRestTimerSeconds: 90,
            syncOwnerTokenIdentifier: ownerTokenIdentifier
        )
        let localSettings = UserSettings(defaultRestTimerSeconds: 240)
        context.insert(ownedSettings)
        context.insert(localSettings)
        try context.save()

        try SyncCoordinator(client: FakeSyncClient())
            .prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

        XCTAssertNil(localSettings.syncOwnerTokenIdentifier)
        XCTAssertEqual(ownedSettings.defaultRestTimerSeconds, 90)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<UserSettings>())
                .filter { $0.syncOwnerTokenIdentifier == ownerTokenIdentifier }
                .count,
            1
        )
    }

    /// The reported P1: `mergeSeedExercise` reads an active outbox entry as the
    /// durable "the user edited this while signed out" signal. Without it an edited
    /// duplicate is indistinguishable from a fresh re-seed and gets deleted with the
    /// edit uncopied.
    func testSignedOutEditToDuplicateSeedSurvivesMergeIntoCanonicalSeed() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(bootstrappedCursorState())
        let canonical = Exercise(
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true,
            syncOwnerTokenIdentifier: ownerTokenIdentifier,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let duplicate = Exercise(
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(canonical)
        context.insert(duplicate)
        try context.save()

        // Signed out, the user renames the re-seeded duplicate.
        let scheduler = SyncScheduler()
        try ExerciseMutationService(
            syncOutboxTransaction: SyncOutboxTransaction(modelContext: context, syncScheduler: scheduler)
        ).updateExercise(
            duplicate,
            name: "Bench Press (Wide)",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            notes: "Wider grip",
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )

        try SyncCoordinator(client: FakeSyncClient())
            .prepareForSync(ownerTokenIdentifier: ownerTokenIdentifier, context: context)

        XCTAssertEqual(canonical.name, "Bench Press (Wide)")
        XCTAssertEqual(canonical.notes, "Wider grip")
    }

    // MARK: - Helpers


    private func bootstrappedCursorState() -> SyncCursorState {
        SyncCursorState(
            ownerTokenIdentifier: ownerTokenIdentifier,
            hasBootstrappedSettingsExercises: true
        )
    }

    private func outboxEntries(in context: ModelContext) -> [SyncOutboxEntry] {
        (try? context.fetch(FetchDescriptor<SyncOutboxEntry>())) ?? []
    }
}
