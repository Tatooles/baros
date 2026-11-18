import XCTest
@testable import Baros
@testable import BarosCore

final class ExercisePickerModeTests: XCTestCase {
    func testSwapModeTreatsOnlyTheExactCurrentExerciseAsUnavailable() {
        let current = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let sameNameVariant = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscleGroup: .chest
        )
        let mode = ExercisePickerMode.swap(
            SwapExerciseImpact(original: LoggedExercise(orderIndex: 0, exercise: current))
        )

        XCTAssertTrue(mode.isCurrent(current))
        XCTAssertFalse(mode.isCurrent(sameNameVariant))
    }
}

final class ExercisePickerContentTests: XCTestCase {
    private func exercise(
        named name: String,
        equipment: ExerciseEquipment = .barbell,
        muscleGroup: ExerciseMuscleGroup = .chest
    ) -> Exercise {
        Exercise(
            name: name,
            category: .strength,
            equipment: equipment,
            primaryMuscleGroup: muscleGroup
        )
    }
}
