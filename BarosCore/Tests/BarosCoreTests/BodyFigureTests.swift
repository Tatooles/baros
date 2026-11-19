import XCTest
@testable import BarosCore

final class BodyFigureTests: XCTestCase {
    func testPickerSectionsListEveryMuscleGroupOnce() {
        let listed = ExerciseMuscleGroup.pickerSections.flatMap(\.groups)
        XCTAssertEqual(listed.count, ExerciseMuscleGroup.allCases.count)
        XCTAssertEqual(Set(listed), Set(ExerciseMuscleGroup.allCases))
    }
}
