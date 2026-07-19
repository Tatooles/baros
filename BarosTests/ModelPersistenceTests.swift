import SwiftData
import XCTest
@testable import Baros

@MainActor
final class ModelPersistenceTests: XCTestCase {
    func testCreatingExerciseSavesAndFetchesByID() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Safety Bar Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads
        )

        context.insert(exercise)
        try context.save()

        let id = exercise.id
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.name, "Safety Bar Squat")
        XCTAssertEqual(fetched.first?.category, .strength)
    }

    func testExerciseMuscleGroupDisplayNamesAndFallback() throws {
        XCTAssertEqual(ExerciseMuscleGroup.chest.displayName, "Chest")
        XCTAssertEqual(ExerciseMuscleGroup.upperBack.displayName, "Upper Back")
        XCTAssertEqual(ExerciseMuscleGroup.lowerBack.displayName, "Lower Back")
        XCTAssertEqual(ExerciseMuscleGroup.fullBody.displayName, "Full Body")
        XCTAssertEqual(ExerciseMuscleGroup(rawValue: "futureValue") ?? .other, .other)
    }

    func testExerciseMuscleGroupMapsLegacyValues() throws {
        XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Quads"), .quads)
        XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Glutes"), .glutes)
        XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Rear Delts"), .shoulders)
        XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Abdominals"), .core)
        XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Lower Back"), .lowerBack)
        XCTAssertEqual(ExerciseMuscleGroup.legacyGroup(for: "Unknown Muscle"), .other)
    }

    func testExercisePersistsPrimaryMuscleGroupAndMetadataDisplay() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )

        context.insert(exercise)
        try context.save()

        let id = exercise.id
        let fetched = try XCTUnwrap(
            context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first
        )
        XCTAssertEqual(fetched.primaryMuscleGroup, .chest)
        XCTAssertEqual(fetched.primaryMuscleGroupRaw, "chest")
        XCTAssertEqual(fetched.metadataDisplayText, "Barbell • Chest")
    }

    func testExerciseUnknownPrimaryMuscleGroupFallsBackToOther() throws {
        let exercise = Exercise(
            name: "Mystery Lift",
            category: .strength,
            equipment: .other,
            primaryMuscleGroup: .other
        )
        exercise.primaryMuscleGroupRaw = "futureGroup"

        XCTAssertEqual(exercise.primaryMuscleGroup, .other)
        XCTAssertEqual(exercise.primaryMuscleGroupRaw, "futureGroup")
        XCTAssertEqual(exercise.metadataDisplayText, "Other • Other")
    }

    func testExercisePrimaryMuscleGroupFallsBackToLegacyRawWhenDefaulted() throws {
        let exercise = Exercise(name: "Legacy Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .other)
        exercise.primaryMuscleRaw = "Chest"
        exercise.primaryMuscleGroupRaw = ExerciseMuscleGroup.other.rawValue

        XCTAssertEqual(exercise.primaryMuscleGroup, .chest)
        XCTAssertEqual(exercise.metadataDisplayText, "Barbell • Chest")
    }

    func testExerciseActiveIdentityTrimsCandidateName() throws {
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)

        XCTAssertTrue(exercise.hasSameActiveIdentity(name: "  Bench Press  ", equipment: .barbell))
    }

    func testLoggedExerciseSnapshotsExerciseMetadata() throws {
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise)

        XCTAssertEqual(loggedExercise.exerciseSnapshotName, "Bench Press")
        XCTAssertEqual(loggedExercise.exerciseSnapshotEquipmentRaw, "barbell")
        XCTAssertEqual(loggedExercise.exerciseSnapshotPrimaryMuscleGroupRaw, "chest")
        XCTAssertEqual(loggedExercise.metadataDisplayText, "Barbell • Chest")
    }

    func testLoggedExerciseSnapshotsResolvedLegacyPrimaryMuscleGroup() throws {
        let exercise = Exercise(name: "Legacy Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .other)
        exercise.primaryMuscleRaw = "Chest"
        exercise.primaryMuscleGroupRaw = ExerciseMuscleGroup.other.rawValue

        let loggedExercise = LoggedExercise(orderIndex: 0, exercise: exercise)

        XCTAssertEqual(loggedExercise.exerciseSnapshotPrimaryMuscleGroupRaw, "chest")
        XCTAssertEqual(loggedExercise.metadataDisplayText, "Barbell • Chest")
    }

    func testLoggedExerciseFallsBackToLinkedExerciseMetadataForDefaultedSnapshots() throws {
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.other.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.other.rawValue
        )
        loggedExercise.hasSnapshotMetadata = false

        XCTAssertEqual(loggedExercise.metadataDisplayText, "Barbell • Chest")
        XCTAssertEqual(loggedExercise.effectiveSnapshotEquipmentRaw, "barbell")
        XCTAssertEqual(loggedExercise.effectiveSnapshotPrimaryMuscleGroupRaw, "chest")
    }

    func testLoggedExerciseSuppressesUnknownDefaultedSnapshotMetadata() throws {
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: nil,
            exerciseSnapshotName: "Legacy Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.other.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.other.rawValue
        )
        loggedExercise.hasSnapshotMetadata = false

        XCTAssertNil(loggedExercise.metadataDisplayText)
        XCTAssertNil(loggedExercise.resolvedSnapshotEquipmentRaw)
        XCTAssertNil(loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw)
        XCTAssertEqual(loggedExercise.effectiveSnapshotEquipmentRaw, "other")
        XCTAssertEqual(loggedExercise.effectiveSnapshotPrimaryMuscleGroupRaw, "other")
    }

    func testLoggedExercisePreservesExplicitOtherSnapshotMetadata() throws {
        let exercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let loggedExercise = LoggedExercise(
            orderIndex: 0,
            exercise: exercise,
            exerciseSnapshotName: "Bench Press",
            exerciseSnapshotEquipmentRaw: ExerciseEquipment.other.rawValue,
            exerciseSnapshotPrimaryMuscleGroupRaw: ExerciseMuscleGroup.other.rawValue
        )

        exercise.equipment = .dumbbell
        exercise.primaryMuscleGroup = .shoulders

        XCTAssertTrue(loggedExercise.hasSnapshotMetadata)
        XCTAssertEqual(loggedExercise.metadataDisplayText, "Other • Other")
        XCTAssertEqual(loggedExercise.effectiveSnapshotEquipmentRaw, "other")
        XCTAssertEqual(loggedExercise.effectiveSnapshotPrimaryMuscleGroupRaw, "other")
    }

    func testExpandedExerciseEquipmentDisplayNames() throws {
        XCTAssertEqual(ExerciseEquipment.smithMachine.displayName, "Smith Machine")
        XCTAssertEqual(ExerciseEquipment.resistanceBand.displayName, "Resistance Band")
        XCTAssertEqual(ExerciseEquipment.medicineBall.displayName, "Medicine Ball")
    }

    func testWorkoutSessionPersistsLoggedExerciseAndSetRelationships() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
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
            primaryMuscleGroup: .quads,
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
            primaryMuscleGroup: .chest,
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
            primaryMuscleGroup: .hamstrings,
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
        let visible = Exercise(name: "Bench Press", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let archived = Exercise(name: "Archived Squat", category: .strength, equipment: .barbell, primaryMuscleGroup: .quads, isArchived: true)
        let deleted = Exercise(name: "Deleted Deadlift", category: .strength, equipment: .barbell, primaryMuscleGroup: .upperBack)
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

    func testVisibleActiveExercisesRespectCurrentSyncOwner() throws {
        let localExercise = Exercise(name: "Local Bench", category: .strength, equipment: .barbell, primaryMuscleGroup: .chest)
        let ownerExercise = Exercise(
            name: "Owner Squat",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .quads,
            syncOwnerTokenIdentifier: "issuer|owner_a"
        )
        let otherOwnerExercise = Exercise(
            name: "Other Deadlift",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .glutes,
            syncOwnerTokenIdentifier: "issuer|owner_b"
        )

        let signedInExercises = Exercise.visibleActiveExercises(
            from: [otherOwnerExercise, localExercise, ownerExercise],
            ownerTokenIdentifier: "issuer|owner_a"
        )
        let signedOutExercises = Exercise.visibleActiveExercises(
            from: [otherOwnerExercise, localExercise, ownerExercise],
            ownerTokenIdentifier: nil
        )

        XCTAssertEqual(signedInExercises.map(\.id), [ownerExercise.id])
        XCTAssertEqual(signedOutExercises.map(\.id), [localExercise.id])
    }

    func testVisibleSettingsRecordsRespectCurrentSyncOwner() throws {
        let localSettings = UserSettings(weightUnit: .pounds)
        let ownerSettings = UserSettings(weightUnit: .kilograms, syncOwnerTokenIdentifier: "issuer|owner_a")
        let otherOwnerSettings = UserSettings(weightUnit: .pounds, syncOwnerTokenIdentifier: "issuer|owner_b")

        let signedInSettings = UserSettings.visibleSettingsRecords(
            from: [otherOwnerSettings, localSettings, ownerSettings],
            ownerTokenIdentifier: "issuer|owner_a"
        )
        let signedOutSettings = UserSettings.visibleSettingsRecords(
            from: [otherOwnerSettings, localSettings, ownerSettings],
            ownerTokenIdentifier: nil
        )

        XCTAssertEqual(signedInSettings.map(\.id), [ownerSettings.id])
        XCTAssertEqual(signedOutSettings.map(\.id), [localSettings.id])
    }

    func testCustomExerciseCanBeCreatedEditedAndArchived() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Seal Row", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .upperBack)

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
        let exercise = Exercise(name: "Seal Row", category: .strength, equipment: .dumbbell, primaryMuscleGroup: .upperBack)

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
            primaryMuscleGroup: .chest,
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
