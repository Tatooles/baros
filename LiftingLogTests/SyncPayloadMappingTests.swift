import XCTest
@testable import LiftingLog

final class SyncPayloadMappingTests: XCTestCase {
    func testUserSettingsPayloadUsesClientIdAndUnixSeconds() throws {
        let settings = UserSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            weightUnit: .kilograms,
            defaultRestTimerSeconds: 120,
            hasCompletedOnboarding: true,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            deletedAt: nil
        )

        let payload = SyncPayloadMapper.userSettingsPayload(from: settings)

        XCTAssertEqual(payload.clientId, "00000000-0000-0000-0000-000000001001")
        XCTAssertEqual(payload.weightUnitRaw, "kilograms")
        XCTAssertEqual(payload.defaultRestTimerSeconds, 120)
        XCTAssertTrue(payload.hasCompletedOnboarding)
        XCTAssertEqual(payload.createdAt, 10)
        XCTAssertEqual(payload.updatedAt, 20)
        XCTAssertNil(payload.deletedAt)
    }

    func testExercisePayloadPreservesRawTaxonomyStrings() throws {
        let exercise = Exercise(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001002")!,
            seedIdentifier: "seed-bench",
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest,
            notes: "Pause reps",
            isArchived: true,
            isSeeded: true,
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40),
            deletedAt: Date(timeIntervalSince1970: 50)
        )
        exercise.categoryRaw = "future-strength"
        exercise.equipmentRaw = "future-bar"
        exercise.primaryMuscleRaw = "Future Chest"
        exercise.primaryMuscleGroupRaw = "future-chest"

        let payload = SyncPayloadMapper.exercisePayload(from: exercise)

        XCTAssertEqual(payload.clientId, "00000000-0000-0000-0000-000000001002")
        XCTAssertEqual(payload.seedIdentifier, "seed-bench")
        XCTAssertEqual(payload.name, "Bench Press")
        XCTAssertEqual(payload.categoryRaw, "future-strength")
        XCTAssertEqual(payload.equipmentRaw, "future-bar")
        XCTAssertEqual(payload.primaryMuscleRaw, "Future Chest")
        XCTAssertEqual(payload.primaryMuscleGroupRaw, "future-chest")
        XCTAssertEqual(payload.notes, "Pause reps")
        XCTAssertTrue(payload.isArchived)
        XCTAssertTrue(payload.isSeeded)
        XCTAssertEqual(payload.createdAt, 30)
        XCTAssertEqual(payload.updatedAt, 40)
        XCTAssertEqual(payload.deletedAt, 50)
    }

    func testFetchChangesRequestCarriesWorkoutGraphCursors() throws {
        let cursors = SyncChangeCursors(
            userSettings: 10,
            exercises: 20,
            workoutSessions: 30,
            loggedExercises: 40,
            loggedSets: 50
        )

        XCTAssertEqual(cursors.userSettings, 10)
        XCTAssertEqual(cursors.exercises, 20)
        XCTAssertEqual(cursors.workoutSessions, 30)
        XCTAssertEqual(cursors.loggedExercises, 40)
        XCTAssertEqual(cursors.loggedSets, 50)
    }

    func testWorkoutSessionPayloadMapsCompletedSessionFields() throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000004001")!
        let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000004099")!
        let healthID = UUID(uuidString: "00000000-0000-0000-0000-000000004098")!
        let session = WorkoutSession(
            id: sessionID,
            title: "Push Day",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 220),
            durationSeconds: 120,
            notes: "Felt strong",
            status: .completed,
            source: .pastWorkout,
            sourceSessionID: sourceID,
            referenceNotes: "Repeat this",
            createdAt: Date(timeIntervalSince1970: 90),
            updatedAt: Date(timeIntervalSince1970: 230),
            deletedAt: nil,
            healthLinkID: healthID
        )

        let payload = SyncPayloadMapper.workoutSessionPayload(from: session)

        XCTAssertEqual(payload.clientId, sessionID.uuidString.lowercased())
        XCTAssertEqual(payload.title, "Push Day")
        XCTAssertEqual(payload.startedAt, 100)
        XCTAssertEqual(payload.endedAt, 220)
        XCTAssertEqual(payload.durationSeconds, 120)
        XCTAssertEqual(payload.notes, "Felt strong")
        XCTAssertEqual(payload.referenceNotes, "Repeat this")
        XCTAssertEqual(payload.statusRaw, "completed")
        XCTAssertEqual(payload.sourceRaw, "pastWorkout")
        XCTAssertEqual(payload.sourceSessionID, sourceID.uuidString.lowercased())
        XCTAssertEqual(payload.healthLinkID, healthID.uuidString.lowercased())
        XCTAssertEqual(payload.createdAt, 90)
        XCTAssertEqual(payload.updatedAt, 230)
        XCTAssertNil(payload.deletedAt)
    }

    func testLoggedExercisePayloadMapsParentAndSnapshotFields() throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000004101")!
        let exerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000004102")!
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000004103")!
        let exercise = Exercise(
            id: exerciseID,
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let session = WorkoutSession(title: "Push", startedAt: Date(timeIntervalSince1970: 50), status: .completed, source: .blank)
        session.id = sessionID
        let loggedExercise = LoggedExercise(
            id: loggedExerciseID,
            orderIndex: 2,
            exercise: exercise,
            exerciseSnapshotName: "Snapshot Bench",
            exerciseSnapshotEquipmentRaw: "smithMachine",
            exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
            notes: "Paused",
            referenceNotes: "Old notes",
            createdAt: Date(timeIntervalSince1970: 60),
            updatedAt: Date(timeIntervalSince1970: 70),
            deletedAt: Date(timeIntervalSince1970: 80)
        )
        loggedExercise.session = session

        let payload = SyncPayloadMapper.loggedExercisePayload(from: loggedExercise)

        XCTAssertEqual(payload.clientId, loggedExerciseID.uuidString.lowercased())
        XCTAssertEqual(payload.sessionClientId, sessionID.uuidString.lowercased())
        XCTAssertEqual(payload.exerciseClientId, exerciseID.uuidString.lowercased())
        XCTAssertEqual(payload.orderIndex, 2)
        XCTAssertEqual(payload.exerciseSnapshotName, "Snapshot Bench")
        XCTAssertEqual(payload.exerciseSnapshotEquipmentRaw, "smithMachine")
        XCTAssertEqual(payload.exerciseSnapshotPrimaryMuscleGroupRaw, "chest")
        XCTAssertTrue(payload.hasSnapshotMetadata)
        XCTAssertEqual(payload.notes, "Paused")
        XCTAssertEqual(payload.referenceNotes, "Old notes")
        XCTAssertEqual(payload.createdAt, 60)
        XCTAssertEqual(payload.updatedAt, 70)
        XCTAssertEqual(payload.deletedAt, 80)
    }

    func testLoggedSetPayloadMapsParentAndLiftFields() throws {
        let loggedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000004201")!
        let setID = UUID(uuidString: "00000000-0000-0000-0000-000000004202")!
        let healthID = UUID(uuidString: "00000000-0000-0000-0000-000000004203")!
        let loggedExercise = LoggedExercise(id: loggedExerciseID, orderIndex: 0)
        let set = LoggedSet(
            id: setID,
            orderIndex: 3,
            weight: 185,
            reps: 5,
            rpe: 8.5,
            placeholderWeight: 175,
            placeholderReps: 6,
            placeholderRPE: 7.5,
            kind: .working,
            isCompleted: true,
            completedAt: Date(timeIntervalSince1970: 125),
            notes: "Solid",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 130),
            deletedAt: nil,
            healthLinkID: healthID
        )
        set.loggedExercise = loggedExercise

        let payload = SyncPayloadMapper.loggedSetPayload(from: set)

        XCTAssertEqual(payload.clientId, setID.uuidString.lowercased())
        XCTAssertEqual(payload.loggedExerciseClientId, loggedExerciseID.uuidString.lowercased())
        XCTAssertEqual(payload.orderIndex, 3)
        XCTAssertEqual(payload.weight, 185)
        XCTAssertEqual(payload.reps, 5)
        XCTAssertEqual(payload.rpe, 8.5)
        XCTAssertEqual(payload.placeholderWeight, 175)
        XCTAssertEqual(payload.placeholderReps, 6)
        XCTAssertEqual(payload.placeholderRPE, 7.5)
        XCTAssertEqual(payload.kindRaw, "working")
        XCTAssertTrue(payload.isCompleted)
        XCTAssertEqual(payload.completedAt, 125)
        XCTAssertEqual(payload.notes, "Solid")
        XCTAssertEqual(payload.healthLinkID, healthID.uuidString.lowercased())
        XCTAssertEqual(payload.createdAt, 100)
        XCTAssertEqual(payload.updatedAt, 130)
        XCTAssertNil(payload.deletedAt)
    }
}
