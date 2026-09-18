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

    func testManualFocusCancelsAnInFlightScrollAtItsVisiblePosition() async throws {
        let (window, scroll, marker) = try makeWindowedScroll(markerY: 600)
        defer { window.isHidden = true }
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        animator.reveal(field, anchor: .center)
        try await Task.sleep(for: .milliseconds(80))

        animator.focusDidChange(to: .workoutTitle)
        let stoppedOffset = scroll.contentOffset.y
        XCTAssertGreaterThan(stoppedOffset, 100)
        XCTAssertLessThan(stoppedOffset, 370, "Cancellation must not jump to the animation's destination")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(scroll.contentOffset.y, stoppedOffset, accuracy: 0.5)
    }

    func testRevealWithoutATargetStopsThePreviousScrollBeforeTheFallback() async throws {
        let (window, scroll, marker) = try makeWindowedScroll(markerY: 600)
        defer { window.isHidden = true }
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }
        animator.reveal(field, anchor: .center)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(animator.reveal(.setWeight(UUID()), anchor: .center))
        let stoppedOffset = scroll.contentOffset.y
        XCTAssertGreaterThan(stoppedOffset, 100)
        XCTAssertLessThan(stoppedOffset, 370, "The old scroll must stop where it is, not at its destination")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(scroll.contentOffset.y, stoppedOffset, accuracy: 0.5)
    }

    func testNewNavigationUsesTheLatestTarget() {
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

        XCTAssertEqual(scroll.contentOffset.y, 472, accuracy: 0.5)
    }

    func testMissingTargetsFallBackWithoutChangingScrollPosition() {
        let (scroll, _) = makeScroll(markerY: 600)
        let animator = WorkoutScrollAnimator()
        scroll.contentOffset.y = 200

        XCTAssertFalse(animator.reveal(.setWeight(UUID()), anchor: .center))
        XCTAssertEqual(scroll.contentOffset.y, 200)
    }

    func testKeyboardRevealCannotOverrideAnActiveArrowDestination() async throws {
        let (window, scroll, marker) = try makeWindowedScroll(markerY: 600)
        defer { window.isHidden = true }
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }
        animator.reveal(field, anchor: .center)
        let destination = scroll.contentOffset.y
        try await Task.sleep(for: .milliseconds(80))
        // The detached note supplies a rectangle at a fixed distance from bounds.origin.
        scroll.scrollRectToVisible(CGRect(x: 0, y: scroll.contentOffset.y + 21, width: 40, height: 32), animated: true)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(scroll.contentOffset.y, destination, accuracy: 0.5)
    }

    func testOffsetChangesAfterTheTransitionAreLeftAlone() async throws {
        let (window, scroll, marker) = try makeWindowedScroll(markerY: 600)
        defer { window.isHidden = true }
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }
        animator.reveal(field, anchor: .center)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(scroll.contentOffset.y, 372, accuracy: 0.5)

        // A later scroll-to-top or layout clamp must not snap back to the arrow destination.
        scroll.setContentOffset(CGPoint(x: 0, y: 50), animated: false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(scroll.contentOffset.y, 50, accuracy: 0.5)
    }

    func testUserTrackingCanMoveAwayFromTheArrowDestination() {
        let trackingScroll = TrackingScrollView()
        let (scroll, marker) = makeScroll(markerY: 600, scrolling: trackingScroll)
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }
        animator.reveal(field, anchor: .center)

        trackingScroll.simulatesTracking = true
        scroll.contentOffset.y = 150
        XCTAssertEqual(scroll.contentOffset.y, 150, accuracy: 0.5)
    }

    func testLayoutClampDoesNotCauseAnOffsetCorrectionLoop() {
        let clampingScroll = ClampingScrollView()
        let (_, marker) = makeScroll(markerY: 600, scrolling: clampingScroll)
        let animator = WorkoutScrollAnimator()
        let field = WorkoutField.setWeight(UUID())
        animator.register(marker, for: field)
        defer { animator.cancel() }
        clampingScroll.writes = 0

        animator.reveal(field, anchor: .center)
        XCTAssertEqual(clampingScroll.contentOffset.y, 200, accuracy: 0.5)
        XCTAssertLessThanOrEqual(clampingScroll.writes, 4)
    }

    private final class TrackingScrollView: UIScrollView {
        var simulatesTracking = false
        override var isTracking: Bool { simulatesTracking }
    }

    private final class ClampingScrollView: UIScrollView {
        var writes = 0
        override var contentOffset: CGPoint {
            get { super.contentOffset }
            set {
                writes += 1
                super.contentOffset = CGPoint(x: newValue.x, y: min(newValue.y, 200))
            }
        }
    }

    private func makeScroll(markerY: CGFloat, scrolling: UIScrollView? = nil) -> (UIScrollView, UIView) {
        let scroll = scrolling ?? UIScrollView()
        scroll.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = UIEdgeInsets(top: 40, left: 0, bottom: 20, right: 0)
        scroll.contentSize = CGSize(width: 320, height: 1_200)
        let marker = UIView(frame: CGRect(x: 40, y: markerY, width: 80, height: 44))
        scroll.addSubview(marker)
        return (scroll, marker)
    }

    /// A scroll view in a live window, so property animations produce presentation values.
    private func makeWindowedScroll(markerY: CGFloat) throws -> (UIWindow, UIScrollView, UIView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let (scroll, marker) = makeScroll(markerY: markerY)
        window.addSubview(scroll)
        window.isHidden = false
        window.layoutIfNeeded()
        scroll.contentOffset.y = 100
        CATransaction.flush()
        return (window, scroll, marker)
    }
}
