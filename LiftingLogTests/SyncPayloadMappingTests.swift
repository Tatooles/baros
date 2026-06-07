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

    func testFetchChangesRequestIncludesZeroWorkoutGraphCursors() throws {
        let cursors = SyncChangeCursors(userSettings: 10, exercises: 20)

        XCTAssertEqual(cursors.userSettings, 10)
        XCTAssertEqual(cursors.exercises, 20)
        XCTAssertEqual(cursors.workoutSessions, 0)
        XCTAssertEqual(cursors.loggedExercises, 0)
        XCTAssertEqual(cursors.loggedSets, 0)
    }
}
