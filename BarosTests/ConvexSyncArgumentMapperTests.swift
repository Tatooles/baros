import ConvexMobile
import XCTest
@testable import Baros
@testable import BarosCore

final class ConvexSyncArgumentMapperTests: XCTestCase {
    func testUserSettingsArgsEncodeRestTimerAsDouble() throws {
        let payload = UserSettingsSyncPayload(
            clientId: "settings-1",
            createdAt: 1,
            updatedAt: 2,
            deletedAt: nil,
            weightUnitRaw: "kilograms",
            defaultRestTimerSeconds: 90,
            hasCompletedOnboarding: true
        )

        let record = ConvexSyncArgumentMapper.userSettingsRecord(payload)
        let encodedRestTimer = try XCTUnwrap(try XCTUnwrap(record["defaultRestTimerSeconds"]))

        XCTAssertEqual(encodedRestTimer as? Double, 90)
        XCTAssertFalse(encodedRestTimer is Int)
    }

    func testFetchChangesArgsEncodeLimitAsDouble() throws {
        let args = ConvexSyncArgumentMapper.fetchChangesArgs(
            cursors: SyncChangeCursors(userSettings: 1, exercises: 2),
            limit: 100
        )

        let encodedLimit = try XCTUnwrap(try XCTUnwrap(args["limit"]))

        XCTAssertEqual(encodedLimit as? Double, 100)
        XCTAssertFalse(encodedLimit is Int)
    }

    func testWorkoutSessionArgsEncodeIntegersAsDoubleAndUUIDsAsStrings() throws {
        let payload = WorkoutSessionSyncPayload(
            clientId: "session-1",
            createdAt: 1,
            updatedAt: 2,
            deletedAt: nil,
            title: "Push",
            startedAt: 3,
            endedAt: 4,
            durationSeconds: 60,
            notes: "",
            referenceNotes: nil,
            statusRaw: "completed",
            sourceRaw: "pastWorkout",
            sourceSessionID: "source-1",
            healthLinkID: nil,
            sourceTemplateID: "template-1"
        )

        let record = ConvexSyncArgumentMapper.workoutSessionRecord(payload)

        XCTAssertEqual(try XCTUnwrap(record["durationSeconds"] as? Double), 60)
        XCTAssertEqual(try XCTUnwrap(record["sourceSessionID"] as? String), "source-1")
        XCTAssertEqual(try XCTUnwrap(record["sourceTemplateID"] as? String), "template-1")
        XCTAssertNil(record["healthLinkID"]!)
    }

    func testLoggedExerciseArgsEncodeOrderIndexAsDouble() throws {
        let payload = LoggedExerciseSyncPayload(
            clientId: "logged-exercise-1",
            createdAt: 1,
            updatedAt: 2,
            deletedAt: nil,
            sessionClientId: "session-1",
            exerciseClientId: "exercise-1",
            orderIndex: 7,
            exerciseSnapshotName: "Bench",
            exerciseSnapshotEquipmentRaw: "barbell",
            exerciseSnapshotPrimaryMuscleGroupRaw: "chest",
            hasSnapshotMetadata: true,
            notes: "",
            referenceNotes: nil,
            sourceLoggedExerciseID: "source-logged-exercise-1"
        )

        let record = ConvexSyncArgumentMapper.loggedExerciseRecord(payload)

        XCTAssertEqual(try XCTUnwrap(record["orderIndex"] as? Double), 7)
        XCTAssertEqual(try XCTUnwrap(record["sessionClientId"] as? String), "session-1")
        XCTAssertEqual(try XCTUnwrap(record["sourceLoggedExerciseID"] as? String), "source-logged-exercise-1")
    }

    func testLoggedSetArgsEncodeNullableAndIntegerFields() throws {
        let payload = LoggedSetSyncPayload(
            clientId: "set-1",
            createdAt: 1,
            updatedAt: 2,
            deletedAt: nil,
            loggedExerciseClientId: "logged-exercise-1",
            orderIndex: 1,
            weight: 185,
            reps: 5,
            rpe: nil,
            kindRaw: "working",
            isCompleted: true,
            completedAt: 3,
            notes: "",
            healthLinkID: nil,
            sourceLoggedSetID: "source-logged-set-1"
        )

        let record = ConvexSyncArgumentMapper.loggedSetRecord(payload)

        XCTAssertEqual(try XCTUnwrap(record["orderIndex"] as? Double), 1)
        XCTAssertEqual(try XCTUnwrap(record["reps"] as? Double), 5)
        XCTAssertNil(record["rpe"]!)
        XCTAssertNil(record["healthLinkID"]!)
        XCTAssertEqual(try XCTUnwrap(record["sourceLoggedSetID"] as? String), "source-logged-set-1")
        XCTAssertNil(record.index(forKey: "durationSeconds"), "An unknown time is omitted so the server keeps its value")
    }

    func testTimedExerciseArgsSendTheMethodAndTimeOnlyWhenKnown() throws {
        var set = LoggedSetSyncPayload(
            clientId: "set-1", createdAt: 1, updatedAt: 2, deletedAt: nil,
            loggedExerciseClientId: "logged-exercise-1", orderIndex: 0, weight: nil, reps: nil, rpe: nil,
            kindRaw: "working", isCompleted: true, completedAt: 3, notes: "", healthLinkID: nil,
            sourceLoggedSetID: nil, durationSeconds: 90, sendsDurationSeconds: true
        )
        var record = ConvexSyncArgumentMapper.loggedSetRecord(set)
        XCTAssertEqual(try XCTUnwrap(record["durationSeconds"] as? Double), 90)

        set.durationSeconds = nil
        record = ConvexSyncArgumentMapper.loggedSetRecord(set)
        XCTAssertNotNil(record.index(forKey: "durationSeconds"), "A cleared time is sent as null")
        XCTAssertNil(record["durationSeconds"]!)

        var logged = LoggedExerciseSyncPayload(
            clientId: "logged-exercise-1", createdAt: 1, updatedAt: 2, deletedAt: nil,
            sessionClientId: "session-1", exerciseClientId: nil, orderIndex: 0, exerciseSnapshotName: "Plank",
            exerciseSnapshotEquipmentRaw: "bodyweight", exerciseSnapshotPrimaryMuscleGroupRaw: "core",
            hasSnapshotMetadata: true, notes: "", referenceNotes: nil, sourceLoggedExerciseID: nil
        )
        XCTAssertNil(ConvexSyncArgumentMapper.loggedExerciseRecord(logged).index(forKey: "trackingMethodRaw"))
        logged.trackingMethodRaw = "duration"
        XCTAssertEqual(
            ConvexSyncArgumentMapper.loggedExerciseRecord(logged)["trackingMethodRaw"] as? String, "duration"
        )

        var exercise = ExerciseSyncPayload(
            clientId: "exercise-1", createdAt: 1, updatedAt: 2, deletedAt: nil, seedIdentifier: nil,
            name: "Plank", categoryRaw: "strength", equipmentRaw: "bodyweight", primaryMuscleRaw: "Core",
            primaryMuscleGroupRaw: "core", notes: "", isArchived: false, isSeeded: false
        )
        XCTAssertNil(ConvexSyncArgumentMapper.exerciseRecord(exercise).index(forKey: "trackingMethodRaw"))
        exercise.trackingMethodRaw = "duration"
        XCTAssertEqual(ConvexSyncArgumentMapper.exerciseRecord(exercise)["trackingMethodRaw"] as? String, "duration")
    }
}
