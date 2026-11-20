import Foundation
import SwiftData
import SwiftUI
import XCTest
@testable import Baros
@testable import BarosCore

@MainActor
final class HomeRingModelTests: XCTestCase {
    func testScrubAngleMapsToSlotsCounterclockwiseFromTwelve() {
        func slot(_ x: CGFloat, _ y: CGFloat, _ count: Int) -> Int {
            HomeRingScrubGeometry.slotIndex(at: CGPoint(x: x, y: y), center: CGPoint(x: 100, y: 100), slotCount: count)
        }
        XCTAssertEqual([slot(100, 0, 30), slot(0, 110, 30), slot(100, 200, 30), slot(200, 90, 30)], [0, 8, 15, 23])
        XCTAssertEqual([slot(100, 0, 52), slot(0, 100, 52), slot(100, 200, 52), slot(200, 100, 52)], [0, 13, 26, 39])
        XCTAssertEqual(slot(70, 0, 30), 1)
        XCTAssertEqual(slot(130, 0, 30), 29)
    }
}

final class HomeLayoutTests: XCTestCase {
    func testPortraitIPhoneKeepsTheSingleColumnAndWidthBasedRing() {
        let layout = HomeLayout(size: CGSize(width: 402, height: 780))

        XCTAssertFalse(layout.isWide)
        XCTAssertEqual(layout.ringDiameter, 321.6, accuracy: 0.01)
    }

    func testIPhoneDuoOuterDisplayKeepsTheSingleColumn() {
        let layout = HomeLayout(size: CGSize(width: 383, height: 610),
                                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 83))

        XCTAssertFalse(layout.isWide)
        XCTAssertEqual(layout.ringDiameter, 306.4, accuracy: 0.01)
    }

    func testIPhoneDuoInnerDisplaySplitsTheColumnsAtTheFold() {
        let layout = HomeLayout(size: CGSize(width: 868, height: 630),
                                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 83))

        XCTAssertTrue(layout.isWide)
        XCTAssertEqual(layout.leadingColumnWidth, 427.5, accuracy: 0.01)
        XCTAssertEqual(layout.ringDiameter, 342, accuracy: 0.01)
    }

    func testLeadingSafeAreaInsetStillSplitsAtTheWindowMidpoint() {
        let layout = HomeLayout(size: CGSize(width: 868, height: 630),
                                safeAreaInsets: EdgeInsets(top: 0, leading: 83, bottom: 0, trailing: 0))

        XCTAssertEqual(layout.leadingColumnWidth, 344.5, accuracy: 0.01)
    }

    func testReportedFoldPositionReplacesTheWindowMidpoint() {
        let layout = HomeLayout(size: CGSize(width: 868, height: 630),
                                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 83),
                                foldMidX: 500)

        XCTAssertEqual(layout.leadingColumnWidth, 452, accuracy: 0.01)
    }

    func testLeadingColumnIsClampedToTheContentWidth() {
        let layout = HomeLayout(size: CGSize(width: 600, height: 400),
                                safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 1_000))

        XCTAssertEqual(layout.leadingColumnWidth, 600 - 48 - 48, accuracy: 0.01)
    }

    func testFoldIsTheFirstVerticalDivisionInsideTheWindow() {
        let duoFold = CGRect(x: 455.5, y: 0, width: 40, height: 669)

        XCTAssertEqual(HomeLayout.foldMidX(divisionFrames: [duoFold], width: 867), 475.5)
        XCTAssertNil(HomeLayout.foldMidX(divisionFrames: [], width: 867))
        XCTAssertNil(HomeLayout.foldMidX(divisionFrames: [duoFold], width: 382))
        XCTAssertNil(HomeLayout.foldMidX(divisionFrames: [CGRect(x: 0, y: 300, width: 867, height: 40)],
                                         width: 867))
    }

    func testWideLayoutStartsAtTheMinimumWidthOnlyWhenWiderThanTall() {
        XCTAssertTrue(HomeLayout(size: CGSize(width: 600, height: 599)).isWide)
        XCTAssertFalse(HomeLayout(size: CGSize(width: 599, height: 400)).isWide)
        XCTAssertFalse(HomeLayout(size: CGSize(width: 600, height: 600)).isWide)
    }

    func testShortWideWindowFitsTheRingToTheHeight() {
        let layout = HomeLayout(size: CGSize(width: 900, height: 480))

        XCTAssertTrue(layout.isWide)
        XCTAssertEqual(layout.ringDiameter, 280)
    }
}
