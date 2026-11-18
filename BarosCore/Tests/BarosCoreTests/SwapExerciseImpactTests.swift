import XCTest
@testable import BarosCore

final class SwapExerciseImpactTests: XCTestCase {
    func testLossMessageCountsSetsWithValuesAndTheNoteButNotBlankSets() {
        let original = loggedExercise(exercise(named: "Bench Press"))
        original.sets = [
            LoggedSet(orderIndex: 0, weight: 0),
            LoggedSet(orderIndex: 1, reps: 5),
            LoggedSet(orderIndex: 2, isCompleted: true),
            LoggedSet(orderIndex: 3),
        ]
        var impact = SwapExerciseImpact(original: original)
        XCTAssertTrue(impact.losesWork)
        XCTAssertEqual(impact.lossMessage, "Removes 3 logged sets from Bench Press")

        original.sets = [LoggedSet(orderIndex: 0, isCompleted: true)]
        original.notes = "Pause at the bottom"
        impact = SwapExerciseImpact(original: original)
        XCTAssertEqual(impact.lossMessage, "Removes 1 logged set and the exercise note from Bench Press")

        original.sets = [LoggedSet(orderIndex: 0)]
        original.notes = " \n"
        impact = SwapExerciseImpact(original: original)
        XCTAssertFalse(impact.losesWork)
        XCTAssertEqual(impact.lossMessage, "Bench Press has nothing logged yet")
    }

    func testConfirmTitleNamesEquipmentOnlyForSameNameVariants() {
        let impact = SwapExerciseImpact(original: loggedExercise(exercise(named: "Bench Press")))
        XCTAssertEqual(
            impact.confirmTitle(for: exercise(named: "bench press", equipment: .dumbbell)),
            "Swap for bench press (Dumbbell)"
        )
        XCTAssertEqual(impact.confirmTitle(for: exercise(named: "Overhead Press")), "Swap for Overhead Press")
    }

    func testSimilarRowsArePerformedSameMuscleExercisesMostRecentFirstWithoutTheOriginal() {
        let bench = exercise(named: "Bench Press")
        let incline = exercise(named: "Incline Press")
        let fly = exercise(named: "Cable Fly", equipment: .cable)
        let pushUp = exercise(named: "Push-Up", equipment: .bodyweight)
        let squat = exercise(named: "Back Squat", muscleGroup: .quads)
        let rows = ExercisePickerContent.makeBaseRows(
            exercises: [bench, incline, fly, pushUp, squat],
            sessions: [
                session(at: 100, bench),
                session(at: 200, incline),
                session(at: 300, fly),
                session(at: 400, squat),
            ],
            ownerTokenIdentifier: nil
        )
        let impact = SwapExerciseImpact(original: loggedExercise(bench))

        XCTAssertEqual(impact.similarRows(in: rows).map(\.exercise.name), ["Cable Fly", "Incline Press"])
        XCTAssertEqual(impact.similarRows(in: rows, limit: 1).map(\.exercise.name), ["Cable Fly"])
    }

    func testSimilarRowsAreEmptyWhenTheMuscleGroupIsOther() {
        let mystery = exercise(named: "Mystery Move", muscleGroup: .other)
        let other = exercise(named: "Other Move", muscleGroup: .other)
        let rows = ExercisePickerContent.makeBaseRows(
            exercises: [mystery, other],
            sessions: [session(at: 100, other)],
            ownerTokenIdentifier: nil
        )
        XCTAssertTrue(SwapExerciseImpact(original: loggedExercise(mystery)).similarRows(in: rows).isEmpty)
    }

    private func exercise(
        named name: String,
        equipment: ExerciseEquipment = .barbell,
        muscleGroup: ExerciseMuscleGroup = .chest
    ) -> Exercise {
        Exercise(name: name, category: .strength, equipment: equipment, primaryMuscleGroup: muscleGroup)
    }

    private func loggedExercise(_ exercise: Exercise) -> LoggedExercise {
        LoggedExercise(orderIndex: 0, exercise: exercise, exerciseSnapshotName: exercise.name)
    }

    private func session(at seconds: TimeInterval, _ exercise: Exercise) -> WorkoutSession {
        let logged = loggedExercise(exercise)
        logged.sets = [LoggedSet(orderIndex: 0, weight: 100, reps: 5, isCompleted: true)]
        let session = WorkoutSession(
            title: "Workout",
            startedAt: Date(timeIntervalSince1970: seconds),
            status: .completed,
            source: .blank
        )
        session.loggedExercises = [logged]
        return session
    }
}
