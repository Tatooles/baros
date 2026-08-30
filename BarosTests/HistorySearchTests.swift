import Foundation
import XCTest
@testable import Baros

final class HistorySearchTests: XCTestCase {
    func testWorkoutSearchMatchesTitlesAndExerciseNamesCaseInsensitively() {
        let titleMatch = makeSession(title: "Upper Body", exerciseName: "Barbell Row")
        let exerciseMatch = makeSession(title: "Strength", exerciseName: "Bench Press")
        let nonMatch = makeSession(title: "Conditioning", exerciseName: "Farmer Carry")
        let sessions = [titleMatch, exerciseMatch, nonMatch]
        let searchIndex = WorkoutHistorySearchIndex(sessions: sessions)

        XCTAssertEqual(
            searchIndex.sessions(
                from: sessions,
                matching: "  upper BODY  "
            ).map(\.id),
            [titleMatch.id]
        )
        XCTAssertEqual(
            searchIndex.sessions(
                from: sessions,
                matching: "bEnCh"
            ).map(\.id),
            [exerciseMatch.id]
        )
    }

    func testExerciseSearchMatchesNameAndVisibleMetadataCaseInsensitively() {
        let barbellPress = makeSummary(
            id: "barbell-press",
            name: "Shoulder Press",
            equipment: .barbell,
            muscleGroup: .shoulders
        )
        let smithPress = makeSummary(
            id: "smith-press",
            name: "Shoulder Press",
            equipment: .smithMachine,
            muscleGroup: .upperBack
        )

        XCTAssertEqual(
            HistorySearch.exercises(
                in: [barbellPress, smithPress],
                matching: "  smith MACHINE "
            ).map(\.id),
            [smithPress.id]
        )
        XCTAssertEqual(
            HistorySearch.exercises(
                in: [barbellPress, smithPress],
                matching: "upper BACK"
            ).map(\.id),
            [smithPress.id]
        )
        XCTAssertEqual(
            HistorySearch.exercises(
                in: [barbellPress, smithPress],
                matching: "press"
            ).map(\.id),
            [barbellPress.id, smithPress.id]
        )
    }

    func testExerciseSearchMatchesEachAvailableMetadataFieldIndependently() {
        let equipmentOnly = makeSummary(
            id: "equipment-only",
            name: "Legacy Press",
            equipment: .barbell,
            muscleGroup: nil
        )
        let muscleGroupOnly = makeSummary(
            id: "muscle-group-only",
            name: "Legacy Pull",
            equipment: nil,
            muscleGroup: .upperBack
        )

        XCTAssertEqual(
            HistorySearch.exercises(
                in: [equipmentOnly, muscleGroupOnly],
                matching: "barbell"
            ).map(\.id),
            [equipmentOnly.id]
        )
        XCTAssertEqual(
            HistorySearch.exercises(
                in: [equipmentOnly, muscleGroupOnly],
                matching: "upper back"
            ).map(\.id),
            [muscleGroupOnly.id]
        )
    }

    func testWhitespaceOnlySearchIsNotAnActiveQuery() {
        XCTAssertFalse(HistorySearch.hasQuery("  \n\t "))
        XCTAssertTrue(HistorySearch.hasQuery(" bench "))
    }

    private func makeSession(title: String, exerciseName: String) -> WorkoutSession {
        WorkoutSession(
            title: title,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .completed,
            source: .blank,
            loggedExercises: [
                LoggedExercise(
                    orderIndex: 0,
                    exerciseSnapshotName: exerciseName
                ),
            ]
        )
    }

    private func makeSummary(
        id: String,
        name: String,
        equipment: ExerciseEquipment?,
        muscleGroup: ExerciseMuscleGroup?
    ) -> ExerciseHistorySummary {
        ExerciseHistorySummary(
            id: id,
            exerciseID: nil,
            name: name,
            equipmentRaw: equipment?.rawValue,
            primaryMuscleGroupRaw: muscleGroup?.rawValue,
            lastPerformedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedSetCount: 1,
            performanceSessionIDs: [],
            snapshotFallbackIdentities: []
        )
    }
}
