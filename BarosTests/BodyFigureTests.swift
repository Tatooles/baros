import SwiftUI
import XCTest
@testable import Baros

final class BodyFigureTests: XCTestCase {
    private let drawings = [BodyFigureDrawing.frontArtwork, BodyFigureDrawing.backArtwork]
    private let figureSize = CGSize(width: 150, height: 300)

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
            case .fullBody:
                XCTAssertEqual(group.figureParts, Set(BodyFigurePart.allCases.filter { $0.muscleGroup != nil }))
            default:
                XCTAssertFalse(group.figureParts.isEmpty, "\(group)")
                XCTAssertTrue(group.figureParts.allSatisfy { $0.muscleGroup == group }, "\(group)")
            }
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

    func testTappingInsideEachMuscleSelectsItsGroup() throws {
        for drawing in drawings {
            let transform = drawing.transform(fitting: figureSize)
            for region in drawing.regions {
                guard let group = region.part.muscleGroup else { continue }
                let inside = try XCTUnwrap(pointInside(region.path), "\(region.part)")
                XCTAssertEqual(
                    drawing.muscleGroup(at: inside.applying(transform), in: figureSize),
                    group,
                    "\(region.part)"
                )
            }
        }
    }

    func testTapJustOutsideASmallMuscleSelectsTheNearestOne() throws {
        let drawing = BodyFigureDrawing.frontArtwork
        let forearm = try XCTUnwrap(drawing.regions.first { $0.part == .forearm })
        let transform = drawing.transform(fitting: figureSize)
        let edge = forearm.path.boundingRect.applying(transform)
        let nearMiss = CGPoint(x: edge.minX - 4, y: edge.midY)

        XCTAssertEqual(drawing.muscleGroup(at: nearMiss, in: figureSize), .forearms)
    }

    func testTapFarFromAnyMuscleSelectsNothing() {
        let drawing = BodyFigureDrawing.frontArtwork
        XCTAssertNil(drawing.muscleGroup(at: CGPoint(x: 2, y: 2), in: figureSize))
        let head = drawing.regions.first { $0.part == .head }!
        let headTop = CGPoint(x: head.path.boundingRect.midX, y: head.path.boundingRect.minY + 20)
            .applying(drawing.transform(fitting: figureSize))
        XCTAssertNil(drawing.muscleGroup(at: headTop, in: figureSize))
    }

    func testFigureTurnsOnlyWhenTheShownSideLacksTheSelection() {
        XCTAssertEqual(BodyFigureSide.showing(.chest, from: .front), .front)
        XCTAssertEqual(BodyFigureSide.showing(.chest, from: .back), .front)
        XCTAssertEqual(BodyFigureSide.showing(.lats, from: .front), .back)
        XCTAssertEqual(BodyFigureSide.showing(.glutes, from: .front), .back)
        // Drawn on both sides, or on neither: keep the current side.
        XCTAssertEqual(BodyFigureSide.showing(.shoulders, from: .back), .back)
        XCTAssertEqual(BodyFigureSide.showing(.fullBody, from: .back), .back)
        XCTAssertEqual(BodyFigureSide.showing(.cardio, from: .back), .back)
        XCTAssertEqual(BodyFigureSide.showing(.other, from: .front), .front)
    }

    func testPathDataParsesAbsoluteCommands() {
        let path = SVGPathData.path(from: "M10 20L30 20C30 30 30 40 20 40Q10 40 10 30Z")
        XCTAssertEqual(path.boundingRect, CGRect(x: 10, y: 20, width: 20, height: 20))
        XCTAssertTrue(path.contains(CGPoint(x: 15, y: 25)))

        let negative = SVGPathData.path(from: "M-5-5L5-5L5 5Z")
        XCTAssertEqual(negative.boundingRect, CGRect(x: -5, y: -5, width: 10, height: 10))
    }

    private func pointInside(_ path: Path) -> CGPoint? {
        let bounds = path.boundingRect
        let steps = 24
        for row in 0...steps {
            for column in 0...steps {
                let point = CGPoint(
                    x: bounds.minX + bounds.width * CGFloat(column) / CGFloat(steps),
                    y: bounds.minY + bounds.height * CGFloat(row) / CGFloat(steps)
                )
                if path.contains(point) { return point }
            }
        }
        return nil
    }
}
