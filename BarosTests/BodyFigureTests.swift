import SwiftUI
import XCTest
@testable import Baros

final class BodyFigureTests: XCTestCase {
    private let drawings = [BodyFigureDrawing.frontArtwork, BodyFigureDrawing.backArtwork]

    func testPickerSectionsListEveryMuscleGroupOnce() {
        let listed = ExerciseMuscleGroup.pickerSections.flatMap(\.groups)
        XCTAssertEqual(listed.count, ExerciseMuscleGroup.allCases.count)
        XCTAssertEqual(Set(listed), Set(ExerciseMuscleGroup.allCases))
    }

    func testEveryAnatomicalGroupHighlightsADrawnRegion() {
        let drawnParts = Set(drawings.flatMap { $0.regions.map(\.part) })
        XCTAssertEqual(drawnParts, Set(BodyFigurePart.allCases))

        for group in ExerciseMuscleGroup.allCases {
            switch group {
            case .cardio, .other:
                XCTAssertTrue(group.figureParts.isEmpty, "\(group)")
            case .fullBody, .upperBody, .lowerBody:
                continue
            default:
                XCTAssertFalse(group.figureParts.isEmpty, "\(group)")
                XCTAssertTrue(group.figureParts.allSatisfy { $0.muscleGroup == group }, "\(group)")
            }
        }
    }

    func testUpperAndLowerBodySplitFullBodyAtTheWaist() {
        let muscles = Set(BodyFigurePart.allCases.filter { $0.muscleGroup != nil })
        let upper = ExerciseMuscleGroup.upperBody.figureParts
        let lower = ExerciseMuscleGroup.lowerBody.figureParts

        XCTAssertEqual(ExerciseMuscleGroup.fullBody.figureParts, muscles)
        XCTAssertEqual(upper.union(lower), muscles)
        XCTAssertTrue(upper.isDisjoint(with: lower))
        XCTAssertTrue(upper.isSuperset(of: [.chest, .abs, .lowerBack, .forearm]))
        XCTAssertTrue(lower.isSuperset(of: [.gluteal, .gluteusMedius, .quadriceps, .calves]))
    }

    func testUpperAndLowerMenuGroupsMatchWhatTheirBodyHalfHighlights() throws {
        for (title, half) in [("Upper", ExerciseMuscleGroup.upperBody), ("Lower", .lowerBody)] {
            let section = try XCTUnwrap(ExerciseMuscleGroup.pickerSections.first { $0.title == title })
            XCTAssertEqual(section.groups.first, half)
            let muscles = section.groups.dropFirst().map(\.figureParts).reduce(Set()) { $0.union($1) }
            XCTAssertEqual(muscles, half.figureParts, title)
        }
    }

    func testRegionsStayInsideTheirFigureBounds() {
        for drawing in drawings {
            for region in drawing.regions {
                XCTAssertFalse(region.path.isEmpty, "\(region.part)")
                XCTAssertTrue(drawing.bounds.insetBy(dx: -1, dy: -1).contains(region.path.boundingRect), "\(region.part)")
            }
        }
    }

    func testPathDataParsesAbsoluteCommands() {
        let path = SVGPathData.path(from: "M10 20L30 20C30 30 30 40 20 40Q10 40 10 30Z")
        XCTAssertEqual(path.boundingRect, CGRect(x: 10, y: 20, width: 20, height: 20))
        XCTAssertTrue(path.contains(CGPoint(x: 15, y: 25)))

        let negative = SVGPathData.path(from: "M-5-5L5-5L5 5Z")
        XCTAssertEqual(negative.boundingRect, CGRect(x: -5, y: -5, width: 10, height: 10))
    }
}
