import SwiftData
import XCTest
@testable import Baros

@MainActor
final class SeedDataServiceTests: XCTestCase {
    func testSeedServiceInsertsExpectedExercises() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.filter(\.isSeeded).count, 20)
        let backSquat = try XCTUnwrap(exercises.first { $0.seedIdentifier == "back-squat" })
        XCTAssertEqual(backSquat.name, "Back Squat")
        XCTAssertEqual(backSquat.category, .strength)
        XCTAssertEqual(backSquat.equipment, .barbell)
    }

    func testSeedServiceUsesControlledPrimaryMuscleGroups() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.first { $0.seedIdentifier == "back-squat" }?.primaryMuscleGroup, .quads)
        XCTAssertEqual(exercises.first { $0.seedIdentifier == "conventional-deadlift" }?.primaryMuscleGroup, .glutes)
        XCTAssertEqual(exercises.first { $0.seedIdentifier == "pull-up" }?.primaryMuscleGroup, .lats)
        XCTAssertEqual(exercises.first { $0.seedIdentifier == "barbell-row" }?.primaryMuscleGroup, .upperBack)
        XCTAssertEqual(exercises.first { $0.seedIdentifier == "face-pull" }?.primaryMuscleGroup, .shoulders)
    }

    func testSeedServiceMigratesLegacyPrimaryMuscleStrings() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let createdAt = Date(timeIntervalSince1970: 100)
        let exercise = Exercise(
            name: "Legacy Face Pull",
            category: .strength,
            equipment: .cable,
            primaryMuscleGroup: .other,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        exercise.primaryMuscleRaw = "Rear Delts"
        exercise.primaryMuscleGroupRaw = ExerciseMuscleGroup.other.rawValue
        context.insert(exercise)

        try SeedDataService.seedIfNeeded(context: context)

        XCTAssertEqual(exercise.primaryMuscleGroupRaw, ExerciseMuscleGroup.shoulders.rawValue)
        XCTAssertEqual(exercise.primaryMuscleRaw, ExerciseMuscleGroup.shoulders.displayName)
        XCTAssertEqual(exercise.primaryMuscleGroup, .shoulders)
        XCTAssertGreaterThan(exercise.updatedAt, createdAt)
    }

    func testSeedServiceIsIdempotent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)
        try SeedDataService.seedIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let metadata = try context.fetch(FetchDescriptor<SeedMetadata>())
        XCTAssertEqual(exercises.filter(\.isSeeded).count, 20)
        XCTAssertEqual(metadata.filter { $0.key == "exerciseSeed" }.count, 1)
    }

    func testSettingsSingletonIsCreatedExactlyOnce() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)
        try SeedDataService.seedIfNeeded(context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<UserSettings>()).count, 1)
    }

    func testSeedServiceCreatesDefaultsForActiveOwnerWhenOtherOwnerRowsExist() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let otherOwnerSettings = UserSettings(syncOwnerTokenIdentifier: "issuer|owner_a")
        let otherOwnerBench = Exercise(
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest,
            isSeeded: true,
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        context.insert(otherOwnerSettings)
        context.insert(otherOwnerBench)
        try context.save()

        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_b")

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: "issuer|owner_b").count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: "issuer|owner_b")
                .filter(\.isSeeded)
                .count,
            20
        )
        XCTAssertEqual(otherOwnerSettings.syncOwnerTokenIdentifier, "issuer|owner_a")
        XCTAssertEqual(otherOwnerBench.syncOwnerTokenIdentifier, "issuer|owner_a")
    }

    func testOwnerScopedSeedServiceIsIdempotent() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_b")
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_b")

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(settings.filter { $0.syncOwnerTokenIdentifier == "issuer|owner_b" }.count, 1)
        XCTAssertEqual(exercises.filter { $0.syncOwnerTokenIdentifier == "issuer|owner_b" && $0.isSeeded }.count, 20)
    }

    func testStartupSeedDoesNotCreateUnownedDefaultsWhenOwnedDefaultsExist() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_b")
        try SeedDataService.seedIfNeeded(context: context, ownerlessScope: .allExisting)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(exercises.filter(\.isSeeded).count, 20)
        XCTAssertTrue(settings.allSatisfy { $0.syncOwnerTokenIdentifier == "issuer|owner_b" })
        XCTAssertTrue(exercises.filter(\.isSeeded).allSatisfy { $0.syncOwnerTokenIdentifier == "issuer|owner_b" })
    }

    func testOwnerScopedSeedDoesNotDuplicateClaimableOwnerlessDefaults() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)
        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_b")

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(exercises.filter(\.isSeeded).count, 20)
        XCTAssertTrue(settings.allSatisfy { $0.syncOwnerTokenIdentifier == nil })
        XCTAssertTrue(exercises.filter(\.isSeeded).allSatisfy { $0.syncOwnerTokenIdentifier == nil })
    }

    func testOwnerScopedSeedCanClaimVisibleOwnerlessDefaultsForFirstOwnerSync() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)
        try SeedDataService.seedIfNeeded(
            context: context,
            ownerTokenIdentifier: "issuer|owner_b",
            claimOwnerlessVisibleDefaults: true
        )

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(exercises.filter(\.isSeeded).count, 20)
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: "issuer|owner_b").count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: "issuer|owner_b")
                .filter(\.isSeeded)
                .count,
            20
        )
        XCTAssertTrue(settings.allSatisfy { $0.syncOwnerTokenIdentifier == "issuer|owner_b" })
        XCTAssertTrue(exercises.filter(\.isSeeded).allSatisfy { $0.syncOwnerTokenIdentifier == "issuer|owner_b" })
    }

    func testOwnerlessSeedCreatesVisibleLocalDefaultsWhenOnlyOwnedDefaultsExist() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context, ownerTokenIdentifier: "issuer|owner_b")
        try SeedDataService.seedIfNeeded(context: context)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(
            UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: nil)
                .filter { $0.syncOwnerTokenIdentifier == nil }
                .count,
            1
        )
        XCTAssertEqual(
            Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: nil)
                .filter { $0.syncOwnerTokenIdentifier == nil && $0.isSeeded }
                .count,
            20
        )
    }

    func testUITestCompletedBenchWorkoutFixtureCreatesStableHistoryData() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)
        try UITestFixtureSeeder.seedCompletedBenchWorkout(title: "Fixture Push", context: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let session = try XCTUnwrap(sessions.first { $0.title == "Fixture Push" })
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.durationSeconds, 3_600)
        XCTAssertEqual(session.syncOwnerTokenIdentifier, nil)

        let exercise = try XCTUnwrap(session.sortedLoggedExercises.first)
        XCTAssertEqual(exercise.exerciseSnapshotName, "Bench Press")
        XCTAssertEqual(exercise.snapshotEquipment, .barbell)
        XCTAssertEqual(exercise.snapshotPrimaryMuscleGroup, .chest)

        let set = try XCTUnwrap(exercise.sortedSets.first)
        XCTAssertEqual(set.weight, 185)
        XCTAssertEqual(set.reps, 5)
        XCTAssertEqual(set.rpe, 8)
        XCTAssertTrue(set.isCompleted)
    }
}
