import SwiftUI
import UIKit
import XCTest
@testable import Baros

@MainActor
final class WorkoutScrollAnimatorTests: XCTestCase {
    func testRevealUsesTheVisibleViewportIncludingInsets() {
        let (scroll, marker) = makeScroll(markerY: 600)
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }

        XCTAssertTrue(animator.reveal(field, anchor: .center))
        XCTAssertEqual(scroll.contentOffset.y, 372, accuracy: 0.5)
    }

    func testKeyboardResizeRetargetsTheCurrentField() {
        let (scroll, marker) = makeScroll(markerY: 600)
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }
        animator.reveal(field, anchor: .center)

        scroll.bounds.size.height = 560
        animator.viewportDidChange()

        XCTAssertEqual(scroll.contentOffset.y, 332, accuracy: 0.5)
    }

    func testRevealClampsToTheScrollableRange() {
        let (scroll, marker) = makeScroll(markerY: 0)
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }
        animator.reveal(field, anchor: .center)
        XCTAssertEqual(scroll.contentOffset.y, -40, accuracy: 0.5)

        marker.frame.origin.y = 1_140
        animator.reveal(field, anchor: .center)
        XCTAssertEqual(scroll.contentOffset.y, 740, accuracy: 0.5)
    }

    func testUnregisteringAReplacedMarkerKeepsTheNewTarget() {
        let (scroll, original) = makeScroll(markerY: 600)
        let replacement = UIView(frame: CGRect(x: 40, y: 700, width: 80, height: 44))
        scroll.addSubview(replacement)
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(original, for: field)
        animator.register(replacement, for: field)
        animator.unregister(original, for: field)
        defer { animator.cancel() }

        XCTAssertTrue(animator.reveal(field, anchor: .center))
        XCTAssertEqual(scroll.contentOffset.y, 472, accuracy: 0.5)
    }

    func testDismissalAndManualFocusCancelFutureViewportCorrections() {
        for nextFocus in [nil, WorkoutField.workoutTitle] {
            let (scroll, marker) = makeScroll(markerY: 600)
            let animator = WorkoutScrollAnimator()
            let field = WorkoutField.setWeight(UUID())
            animator.register(marker, for: field)
            animator.reveal(field, anchor: .center)
            animator.focusDidChange(to: nextFocus)
            scroll.contentOffset.y = 200

            scroll.bounds.size.height = 560
            animator.viewportDidChange()

            XCTAssertEqual(scroll.contentOffset.y, 200, accuracy: 0.5)
        }
    }

    func testNewNavigationOwnsSubsequentViewportCorrections() {
        let (scroll, first) = makeScroll(markerY: 600)
        let second = UIView(frame: CGRect(x: 40, y: 700, width: 80, height: 44))
        scroll.addSubview(second)
        let firstField = WorkoutField.setWeight(UUID())
        let secondField = WorkoutField.setWeight(UUID())
        let animator = WorkoutScrollAnimator()
        animator.register(first, for: firstField)
        animator.register(second, for: secondField)
        defer { animator.cancel() }
        animator.reveal(firstField, anchor: .center)
        animator.reveal(secondField, anchor: .center)

        scroll.bounds.size.height = 560
        animator.viewportDidChange()

        XCTAssertEqual(scroll.contentOffset.y, 432, accuracy: 0.5)
    }

    func testMissingTargetsFallBackWithoutChangingScrollPosition() {
        let (scroll, _) = makeScroll(markerY: 600)
        let animator = WorkoutScrollAnimator()
        scroll.contentOffset.y = 200

        XCTAssertFalse(animator.reveal(.setWeight(UUID()), anchor: .center))
        XCTAssertEqual(scroll.contentOffset.y, 200)
    }

    private func makeScroll(markerY: CGFloat) -> (UIScrollView, UIView) {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = UIEdgeInsets(top: 40, left: 0, bottom: 20, right: 0)
        scroll.contentSize = CGSize(width: 320, height: 1_200)
        let marker = UIView(frame: CGRect(x: 40, y: markerY, width: 80, height: 44))
        scroll.addSubview(marker)
        return (scroll, marker)
    }
}
