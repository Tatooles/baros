import SwiftUI
import UIKit

/// Owns arrow scrolling on the scroll view's layer, so focus-loss model updates
/// cannot interrupt a SwiftUI-driven, frame-by-frame scroll animation.
@MainActor
final class WorkoutScrollAnimator {
    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    private struct Request {
        let id = UUID()
        let field: WorkoutField
        let anchor: UnitPoint
        let deadline: CFTimeInterval
        let targetY: CGFloat
    }

    private var targets: [AnyHashable: WeakView] = [:]
    private var request: Request?
    private var animator: UIViewPropertyAnimator?
    private weak var scrollView: UIScrollView?

    func register(_ view: UIView, for field: AnyHashable) {
        guard targets[field]?.view !== view else { return }
        targets[field] = WeakView(view)
    }

    func unregister(_ view: UIView, for field: AnyHashable) {
        if targets[field]?.view === view { targets[field] = nil }
    }

    @discardableResult
    func reveal(_ field: WorkoutField, anchor: UnitPoint) -> Bool {
        animate(field, anchor: anchor, deadline: CACurrentMediaTime() + 0.25, flush: true)
    }

    func viewportDidChange() {
        guard let request, let destination = destination(for: request.field, anchor: request.anchor),
              abs(destination.y - request.targetY) > 0.5 else { return }
        _ = animate(request.field, anchor: request.anchor, deadline: request.deadline, flush: false)
    }

    func focusDidChange(to field: WorkoutField?) {
        if let request, request.field != field { cancel() }
    }

    func cancel() {
        request = nil
        if let animator {
            let visibleOffset = scrollView?.layer.presentation()?.bounds.origin
            animator.stopAnimation(true)
            if let visibleOffset, let scrollView {
                scrollView.setContentOffset(visibleOffset, animated: false)
            }
        }
        animator = nil
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

    private func animate(_ field: WorkoutField, anchor: UnitPoint, deadline: CFTimeInterval, flush: Bool) -> Bool {
        guard let destination = destination(for: field, anchor: anchor) else { return false }
        cancel()
        let scroll = destination.scroll
        scrollView = scroll
        let next = Request(field: field, anchor: anchor, deadline: deadline, targetY: destination.y)
        request = next

        guard !UIAccessibility.isReduceMotionEnabled, abs(scroll.contentOffset.y - destination.y) > 0.5 else {
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: destination.y), animated: false)
            return true
        }

        let animation = UIViewPropertyAnimator(duration: max(0.06, deadline - CACurrentMediaTime()), curve: .easeInOut) { [weak scroll] in
            guard let scroll else { return }
            scroll.contentOffset.y = destination.y
        }
        animator = animation
        animation.addCompletion { [weak self] _ in
            guard let self, self.request?.id == next.id else { return }
            self.animator = nil
        }
        animation.startAnimation()
        if flush {
            // Submit the animation before assigning focus. UIKit then sees the
            // destination as visible, and the compositor can keep scrolling
            // while SwiftUI processes the departing field's model update.
            CATransaction.flush()
        }
        return true
    }
}

struct WorkoutScrollViewport: Equatable {
    let size: CGSize
    let insets: EdgeInsets
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
