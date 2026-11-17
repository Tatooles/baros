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
        let mode = ExercisePickerMode.swap(currentExerciseID: current.id)

        XCTAssertTrue(mode.isCurrent(current))
        XCTAssertFalse(mode.isCurrent(sameNameVariant))
    }

    func testSwapConfirmationDistinguishesSameNameEquipmentVariants() {
        let originalExercise = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .barbell,
            primaryMuscleGroup: .chest
        )
        let original = LoggedExercise(orderIndex: 0, exercise: originalExercise)
        let replacement = Exercise(
            name: "Bench Press",
            category: .strength,
            equipment: .dumbbell,
            primaryMuscleGroup: .chest
        )

        let content = SwapExerciseConfirmationContent(
            original: original,
            replacement: replacement
        )

        XCTAssertEqual(
            content.title,
            "Swap Bench Press (Barbell) for Bench Press (Dumbbell)?"
        )
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
