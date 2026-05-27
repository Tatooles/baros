import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class ModelPersistenceTests: XCTestCase {
    func testCreatingExerciseSavesAndFetchesByID() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Safety Bar Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads"
        )

        context.insert(exercise)
        try context.save()

        let id = exercise.id
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.name, "Safety Bar Squat")
        XCTAssertEqual(fetched.first?.category, .strength)
    }

    func testWorkoutSessionPersistsLoggedExerciseAndSetRelationships() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .active, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        let set = LoggedSet(orderIndex: 0, weight: 185, reps: 5, rpe: 8, isCompleted: true)

        loggedExercise.sets.append(set)
        session.loggedExercises.append(loggedExercise)
        context.insert(exercise)
        context.insert(session)
        try context.save()

        let sessionID = session.id
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
        let fetched = try XCTUnwrap(context.fetch(descriptor).first)
        XCTAssertEqual(fetched.loggedExercises.count, 1)
        XCTAssertEqual(fetched.loggedExercises.first?.sets.count, 1)
        XCTAssertEqual(fetched.loggedExercises.first?.sets.first?.completedVolume, 925)
    }

    func testCompletedSetVolumeRequiresWeightRepsAndCompletion() throws {
        let completed = LoggedSet(orderIndex: 0, weight: 100, reps: 5, rpe: nil, isCompleted: true)
        let missingWeight = LoggedSet(orderIndex: 1, weight: nil, reps: 5, rpe: nil, isCompleted: true)
        let missingReps = LoggedSet(orderIndex: 2, weight: 100, reps: nil, rpe: nil, isCompleted: true)
        let incomplete = LoggedSet(orderIndex: 3, weight: 100, reps: 5, rpe: nil, isCompleted: false)

        XCTAssertEqual(completed.completedVolume, 500)
        XCTAssertEqual(missingWeight.completedVolume, 0)
        XCTAssertEqual(missingReps.completedVolume, 0)
        XCTAssertEqual(incomplete.completedVolume, 0)
    }

    func testSyncedModelsDefaultToNotDeleted() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let userSettings = UserSettings(createdAt: createdAt, updatedAt: updatedAt)
        let exercise = Exercise(
            name: "Front Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Quads",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let session = WorkoutSession(
            title: "Legs",
            startedAt: createdAt,
            status: .completed,
            source: .blank,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let loggedSet = LoggedSet(orderIndex: 0, weight: 135, reps: 5, createdAt: createdAt, updatedAt: updatedAt)

        context.insert(userSettings)
        context.insert(exercise)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(loggedSet)
        try context.save()

        let userSettingsID = userSettings.id
        let exerciseID = exercise.id
        let sessionID = session.id
        let loggedExerciseID = loggedExercise.id
        let loggedSetID = loggedSet.id
        let fetchedUserSettings = try XCTUnwrap(
            context.fetch(FetchDescriptor<UserSettings>(predicate: #Predicate { $0.id == userSettingsID })).first
        )
        let fetchedExercise = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })).first
        )
        let fetchedSession = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first
        )
        let fetchedLoggedExercise = try XCTUnwrap(
            context.fetch(FetchDescriptor<LoggedExercise>(predicate: #Predicate { $0.id == loggedExerciseID })).first
        )
        let fetchedLoggedSet = try XCTUnwrap(
            context.fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.id == loggedSetID })).first
        )

        XCTAssertNil(fetchedUserSettings.deletedAt)
        XCTAssertFalse(fetchedUserSettings.isDeleted)
        XCTAssertNil(fetchedExercise.deletedAt)
        XCTAssertFalse(fetchedExercise.isDeleted)
        XCTAssertNil(fetchedSession.deletedAt)
        XCTAssertFalse(fetchedSession.isDeleted)
        XCTAssertNil(fetchedLoggedExercise.deletedAt)
        XCTAssertFalse(fetchedLoggedExercise.isDeleted)
        XCTAssertNil(fetchedLoggedSet.deletedAt)
        XCTAssertFalse(fetchedLoggedSet.isDeleted)
    }

    func testSyncedModelsMarkDeletedPersistsTombstoneTimestamp() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let deletedAt = Date(timeIntervalSince1970: 300)
        let userSettings = UserSettings(createdAt: createdAt, updatedAt: updatedAt)
        let exercise = Exercise(
            name: "Incline Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let session = WorkoutSession(
            title: "Push",
            startedAt: createdAt,
            status: .completed,
            source: .blank,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let loggedSet = LoggedSet(orderIndex: 0, weight: 185, reps: 5, createdAt: createdAt, updatedAt: updatedAt)

        context.insert(userSettings)
        context.insert(exercise)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(loggedSet)
        userSettings.markDeleted(now: deletedAt)
        exercise.markDeleted(now: deletedAt)
        session.markDeleted(now: deletedAt)
        loggedExercise.markDeleted(now: deletedAt)
        loggedSet.markDeleted(now: deletedAt)
        try context.save()

        let userSettingsID = userSettings.id
        let exerciseID = exercise.id
        let sessionID = session.id
        let loggedExerciseID = loggedExercise.id
        let loggedSetID = loggedSet.id
        let fetchedUserSettings = try XCTUnwrap(
            context.fetch(FetchDescriptor<UserSettings>(predicate: #Predicate { $0.id == userSettingsID })).first
        )
        let fetchedExercise = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })).first
        )
        let fetchedSession = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first
        )
        let fetchedLoggedExercise = try XCTUnwrap(
            context.fetch(FetchDescriptor<LoggedExercise>(predicate: #Predicate { $0.id == loggedExerciseID })).first
        )
        let fetchedLoggedSet = try XCTUnwrap(
            context.fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.id == loggedSetID })).first
        )

        XCTAssertEqual(fetchedUserSettings.deletedAt, deletedAt)
        XCTAssertEqual(fetchedUserSettings.updatedAt, deletedAt)
        XCTAssertTrue(fetchedUserSettings.isDeleted)
        XCTAssertEqual(fetchedExercise.deletedAt, deletedAt)
        XCTAssertEqual(fetchedExercise.updatedAt, deletedAt)
        XCTAssertTrue(fetchedExercise.isDeleted)
        XCTAssertEqual(fetchedSession.deletedAt, deletedAt)
        XCTAssertEqual(fetchedSession.updatedAt, deletedAt)
        XCTAssertTrue(fetchedSession.isDeleted)
        XCTAssertEqual(fetchedLoggedExercise.deletedAt, deletedAt)
        XCTAssertEqual(fetchedLoggedExercise.updatedAt, deletedAt)
        XCTAssertTrue(fetchedLoggedExercise.isDeleted)
        XCTAssertEqual(fetchedLoggedSet.deletedAt, deletedAt)
        XCTAssertEqual(fetchedLoggedSet.updatedAt, deletedAt)
        XCTAssertTrue(fetchedLoggedSet.isDeleted)
    }

    func testSyncedModelsRestoreFromDeletionPersistsActiveState() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let createdAt = Date(timeIntervalSince1970: 100)
        let deletedAt = Date(timeIntervalSince1970: 300)
        let restoredAt = Date(timeIntervalSince1970: 400)
        let userSettings = UserSettings(createdAt: createdAt, updatedAt: deletedAt, deletedAt: deletedAt)
        let exercise = Exercise(
            name: "Romanian Deadlift",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Hamstrings",
            createdAt: createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
        let session = WorkoutSession(
            title: "Pull",
            startedAt: createdAt,
            status: .completed,
            source: .blank,
            createdAt: createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: exercise.name,
            createdAt: createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )
        let loggedSet = LoggedSet(
            orderIndex: 0,
            weight: 225,
            reps: 5,
            createdAt: createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )

        context.insert(userSettings)
        context.insert(exercise)
        context.insert(session)
        context.insert(loggedExercise)
        context.insert(loggedSet)
        userSettings.restoreFromDeletion(now: restoredAt)
        exercise.restoreFromDeletion(now: restoredAt)
        session.restoreFromDeletion(now: restoredAt)
        loggedExercise.restoreFromDeletion(now: restoredAt)
        loggedSet.restoreFromDeletion(now: restoredAt)
        try context.save()

        let userSettingsID = userSettings.id
        let exerciseID = exercise.id
        let sessionID = session.id
        let loggedExerciseID = loggedExercise.id
        let loggedSetID = loggedSet.id
        let fetchedUserSettings = try XCTUnwrap(
            context.fetch(FetchDescriptor<UserSettings>(predicate: #Predicate { $0.id == userSettingsID })).first
        )
        let fetchedExercise = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })).first
        )
        let fetchedSession = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first
        )
        let fetchedLoggedExercise = try XCTUnwrap(
            context.fetch(FetchDescriptor<LoggedExercise>(predicate: #Predicate { $0.id == loggedExerciseID })).first
        )
        let fetchedLoggedSet = try XCTUnwrap(
            context.fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.id == loggedSetID })).first
        )

        XCTAssertNil(fetchedUserSettings.deletedAt)
        XCTAssertEqual(fetchedUserSettings.updatedAt, restoredAt)
        XCTAssertFalse(fetchedUserSettings.isDeleted)
        XCTAssertNil(fetchedExercise.deletedAt)
        XCTAssertEqual(fetchedExercise.updatedAt, restoredAt)
        XCTAssertFalse(fetchedExercise.isDeleted)
        XCTAssertNil(fetchedSession.deletedAt)
        XCTAssertEqual(fetchedSession.updatedAt, restoredAt)
        XCTAssertFalse(fetchedSession.isDeleted)
        XCTAssertNil(fetchedLoggedExercise.deletedAt)
        XCTAssertEqual(fetchedLoggedExercise.updatedAt, restoredAt)
        XCTAssertFalse(fetchedLoggedExercise.isDeleted)
        XCTAssertNil(fetchedLoggedSet.deletedAt)
        XCTAssertEqual(fetchedLoggedSet.updatedAt, restoredAt)
        XCTAssertFalse(fetchedLoggedSet.isDeleted)
    }

    func testHealthDataLinkStoresFutureProviderWithoutFrameworkImport() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let localID = UUID()
        let link = HealthDataLink(
            providerRaw: "healthKit",
            localEntityKindRaw: "workoutSession",
            localEntityID: localID,
            externalIdentifier: "external-workout-id",
            externalType: "workout",
            syncStatus: .notSynced
        )

        context.insert(link)
        try context.save()

        let descriptor = FetchDescriptor<HealthDataLink>()
        let fetched = try XCTUnwrap(context.fetch(descriptor).first)
        XCTAssertEqual(fetched.providerRaw, "healthKit")
        XCTAssertEqual(fetched.localEntityID, localID)
    }

    func testWorkoutTemplateCanBeCreatedWithoutDrivingUI() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "Future Template", notes: "Stored for later")

        context.insert(template)
        try context.save()

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        XCTAssertEqual(templates.map(\.name), ["Future Template"])
    }

    func testVisibleActiveExercisesExcludeArchivedAndTombstonedRecords() throws {
        let visible = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscle: "Chest")
        let archived = Exercise(name: "Archived Squat", category: .strength, equipment: .barbell, primaryMuscle: "Quads", isArchived: true)
        let deleted = Exercise(name: "Deleted Deadlift", category: .strength, equipment: .barbell, primaryMuscle: "Back")
        deleted.markDeleted(now: Date(timeIntervalSince1970: 100))

        let exercises = Exercise.visibleActiveExercises(from: [deleted, archived, visible])

        XCTAssertEqual(exercises.map(\.id), [visible.id])
    }

    func testVisibleSettingsRecordsExcludeTombstonedRecords() throws {
        let deletedSettings = UserSettings(createdAt: Date(timeIntervalSince1970: 100))
        deletedSettings.markDeleted(now: Date(timeIntervalSince1970: 200))
        let visibleSettings = UserSettings(weightUnit: .kilograms, createdAt: Date(timeIntervalSince1970: 300))

        let settings = UserSettings.visibleSettingsRecords(from: [deletedSettings, visibleSettings])

        XCTAssertEqual(settings.map(\.id), [visibleSettings.id])
    }

    func testCustomExerciseCanBeCreatedEditedAndArchived() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Seal Row", category: .strength, equipment: .dumbbell, primaryMuscle: "Back")

        context.insert(exercise)
        try context.save()

        exercise.name = "Chest Supported Row"
        exercise.archive()
        try context.save()

        let activeExercises = try context.fetch(FetchDescriptor<Exercise>()).filter { !$0.isArchived }
        XCTAssertFalse(activeExercises.contains { $0.id == exercise.id })
    }

    func testCustomExerciseWithoutHistoryTombstonesInsteadOfHardDeleting() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Seal Row", category: .strength, equipment: .dumbbell, primaryMuscle: "Back")

        context.insert(exercise)
        try context.save()

        let exerciseID = exercise.id
        try exercise.archiveOrDelete(context: context)
        try context.save()

        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        let fetched = try XCTUnwrap(allExercises.first { $0.id == exerciseID })
        XCTAssertTrue(fetched.isDeleted)
        XCTAssertNotNil(fetched.deletedAt)
        XCTAssertFalse(Exercise.visibleActiveExercises(from: allExercises).contains { $0.id == exerciseID })
    }

    func testSeededExerciseWithHistoryArchivesInsteadOfHardDeleting() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            seedIdentifier: "bench-press",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscle: "Chest",
            isSeeded: true
        )
        let session = WorkoutSession(title: "Push", startedAt: .now, status: .completed, source: .blank)
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
        session.loggedExercises.append(loggedExercise)

        context.insert(exercise)
        context.insert(session)
        try context.save()

        try exercise.archiveOrDelete(context: context)
        try context.save()

        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertTrue(allExercises.contains { $0.id == exercise.id && $0.isArchived })
    }
}
