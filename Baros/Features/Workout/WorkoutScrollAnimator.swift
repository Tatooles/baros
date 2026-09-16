import SwiftUI
import UIKit

/// Drives arrow-navigation scrolling directly on the workout `UIScrollView`.
/// SwiftUI's `scrollTo` animation advances frame by frame on the main thread, so
/// the focus-loss commit that follows an arrow press could stall it. A Core
/// Animation scroll submitted before the focus change keeps moving through that work.
@MainActor
final class WorkoutScrollAnimator {
    private struct Request {
        let field: WorkoutField
        let destination: CGFloat
        var didReassert = false
    }

    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    private static let duration: TimeInterval = 0.25

    private var targets: [AnyHashable: WeakView] = [:]
    private var request: Request?
    private var animator: UIViewPropertyAnimator?
    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var offsetObservationExpiry: Task<Void, Never>?
    private var isWritingOffset = false

    func register(_ view: UIView, for field: AnyHashable) {
        guard targets[field]?.view !== view else { return }
        targets[field] = WeakView(view)
    }

    func unregister(_ view: UIView, for field: AnyHashable) {
        if targets[field]?.view === view { targets[field] = nil }
    }

    /// Scrolls `field` into view, replacing any scroll still in flight. Returns
    /// `false` when the field has no marker in the hierarchy so the caller can
    /// fall back to `ScrollViewProxy`.
    @discardableResult
    func reveal(_ field: WorkoutField, anchor: UnitPoint) -> Bool {
        cancel()
        guard let destination = destination(for: field, anchor: anchor) else { return false }
        let scroll = destination.scroll
        scrollView = scroll
        request = Request(field: field, destination: destination.y)

        // On iOS 27 a departing multiline note editor can enqueue one stale
        // keyboard reveal after losing its window. Watch for competing offset
        // writes only while the arrow transition is in flight.
        offsetObservation = scroll.observe(\.contentOffset) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reassertDestinationIfNeeded() }
        }
        offsetObservationExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Self.duration)) } catch { return }
            self?.offsetObservation = nil
        }

        animate(to: destination.y, in: scroll)
        // Also covers a scroll view that clamps the offset synchronously.
        reassertDestinationIfNeeded()
        return true
    }

    /// Manual focus changes (taps, dismissal) take over the viewport.
    func focusDidChange(to field: WorkoutField?) {
        if let request, request.field != field { cancel() }
    }

    func cancel() {
        request = nil
        offsetObservationExpiry?.cancel()
        offsetObservationExpiry = nil
        offsetObservation = nil
        stopAnimationAtVisiblePosition()
    }

    private func destination(for field: WorkoutField, anchor: UnitPoint) -> (scroll: UIScrollView, y: CGFloat)? {
        guard let marker = targets[AnyHashable(field)]?.view else { return nil }
        var ancestor = marker.superview
        while ancestor != nil && !(ancestor is UIScrollView) { ancestor = ancestor?.superview }
        guard let scroll = ancestor as? UIScrollView else { return nil }

        let frame = marker.convert(marker.bounds, to: scroll)
        let inset = scroll.adjustedContentInset
        let visibleHeight = scroll.bounds.height - inset.top - inset.bottom
        let minimum = -inset.top
        let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        let y = frame.minY + frame.height * anchor.y - visibleHeight * anchor.y - inset.top
        return (scroll, min(maximum, max(minimum, y)))
    }

    private func reassertDestinationIfNeeded() {
        guard let request, let scroll = scrollView, !isWritingOffset, !request.didReassert,
              !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating,
              abs(scroll.contentOffset.y - request.destination) > 0.5 else { return }
        // Correct at most once so a clamping scroll view cannot cause a loop.
        self.request?.didReassert = true
        stopAnimationAtVisiblePosition()
        animate(to: request.destination, in: scroll)
    }

    private func stopAnimationAtVisiblePosition() {
        guard let animator else { return }
        let visible = scrollView?.layer.presentation()?.bounds.origin
        animator.stopAnimation(true)
        self.animator = nil
        if let visible, let scrollView {
            write(visible, to: scrollView)
        }
    }

    private func animate(to destination: CGFloat, in scroll: UIScrollView) {
        guard !UIAccessibility.isReduceMotionEnabled, abs(scroll.contentOffset.y - destination) > 0.5 else {
            write(CGPoint(x: scroll.contentOffset.x, y: destination), to: scroll)
            return
        }

        let animation = UIViewPropertyAnimator(duration: Self.duration, curve: .easeInOut) { [weak scroll] in
            scroll?.contentOffset.y = destination
        }
        animation.addCompletion { [weak self, weak animation] _ in
            if let self, self.animator === animation { self.animator = nil }
        }
        animator = animation
        isWritingOffset = true
        animation.startAnimation()
        isWritingOffset = false
        // Commit the animation to the render server before the caller assigns
        // focus, so the focus-loss commit cannot delay its first frame.
        CATransaction.flush()
    }

    private func write(_ offset: CGPoint, to scroll: UIScrollView) {
        isWritingOffset = true
        scroll.setContentOffset(offset, animated: false)
        isWritingOffset = false
    }
}

private struct WorkoutScrollAnimatorKey: EnvironmentKey {
    static let defaultValue: WorkoutScrollAnimator? = nil
}

extension EnvironmentValues {
    var workoutScrollAnimator: WorkoutScrollAnimator? {
        get { self[WorkoutScrollAnimatorKey.self] }
        set { self[WorkoutScrollAnimatorKey.self] = newValue }
    }
}

extension View {
    /// Registers this view's UIKit frame as the scroll destination for `field`.
    func workoutScrollTarget<Focus: Hashable>(_ field: Focus) -> some View {
        modifier(WorkoutScrollTargetModifier(field: AnyHashable(field)))
    }
}

private struct WorkoutScrollTargetModifier: ViewModifier {
    @Environment(\.workoutScrollAnimator) private var animator
    let field: AnyHashable

    func body(content: Content) -> some View {
        content.background {
            if let animator { WorkoutScrollMarker(animator: animator, field: field) }
        }
    }
}

private struct WorkoutScrollMarker: UIViewRepresentable {
    let animator: WorkoutScrollAnimator
    let field: AnyHashable

    final class Coordinator {
        var registration: (animator: WorkoutScrollAnimator, field: AnyHashable)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        if let previous = context.coordinator.registration,
           previous.animator !== animator || previous.field != field {
            previous.animator.unregister(view, for: previous.field)
        }
        animator.register(view, for: field)
        context.coordinator.registration = (animator, field)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        if let registration = coordinator.registration {
            registration.animator.unregister(view, for: registration.field)
        }
    }
}
