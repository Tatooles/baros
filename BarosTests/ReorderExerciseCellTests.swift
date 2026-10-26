import UIKit
import XCTest
@testable import Baros

/// Drives the real cell, in a window, through UIKit animations it can't finish
/// before the next touch or reuse.
@MainActor
final class ReorderExerciseCellTests: XCTestCase {
    private var window: UIWindow!

    override func setUp() async throws {
        try await super.setUp()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        window.isHidden = false
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        try await super.tearDown()
    }

    func testGrabbingARowWhileItClosesKeepsItsTrashForTheDrag() {
        let cell = makeCell()
        cell.setRevealed(true, animated: false)
        cell.setRevealed(false, animated: true)
        settle(for: 0.05)
        let onScreen = cell.layer.presentation()?.bounds.origin.x ?? 0
        XCTAssertGreaterThan(onScreen, 0)

        let pan = ScriptedPan()
        pan.drive(cell, .began, by: 0)
        pan.drive(cell, .changed, by: -30)
        // The drag picks the row up where it was on screen rather than where it was headed.
        XCTAssertEqual(cell.bounds.origin.x, onScreen + 30, accuracy: 1)

        // The finger stays down past the close animation's end.
        let lift = Date().addingTimeInterval(1.5)
        while Date() < lift {
            settle(for: 1.0 / 60)
            pan.drive(cell, .changed, by: -30)
        }
        XCTAssertFalse(cell.removeButton.isHidden, "The close animation's completion hid the trash mid-drag.")
        XCTAssertGreaterThan(cell.removeButton.alpha, 0)
    }

    func testReusingARowMidSlideShowsItAtRest() {
        let cell = makeCell()
        cell.setRevealed(true, animated: false)
        cell.slideOut()
        settle(for: 0.02)

        cell.prepareForReuse()
        settle(for: 0.05)

        XCTAssertEqual(cell.layer.presentation()?.bounds.origin.x ?? cell.bounds.origin.x, 0, accuracy: 0.5)
        XCTAssertTrue(cell.removeButton.isHidden)
        XCTAssertEqual(cell.removeButton.layer.presentation()?.opacity ?? 1, 0, accuracy: 0.01)
    }

    private func makeCell() -> ReorderExerciseCell {
        let cell = ReorderExerciseCell(style: .default, reuseIdentifier: "Exercise")
        cell.frame = CGRect(x: 0, y: 0, width: 390, height: 80)
        window.addSubview(cell)
        cell.layoutIfNeeded()
        return cell
    }

    private func settle(for seconds: TimeInterval = 1.5) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

/// Feeds the cell's own pan handler a horizontal drag; UIKit fails a real
/// recognizer whose state is set without touches.
private final class ScriptedPan: UIPanGestureRecognizer {
    private var scriptedState: UIGestureRecognizer.State = .possible
    private var scriptedTranslation: CGFloat = 0

    func drive(_ cell: ReorderExerciseCell, _ state: UIGestureRecognizer.State, by translation: CGFloat) {
        scriptedState = state
        scriptedTranslation = translation
        cell.perform(NSSelectorFromString("handlePan:"), with: self)
    }

    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set { scriptedState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { CGPoint(x: scriptedTranslation, y: 0) }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}
