import SwiftUI
import UIKit

/// Swipe left to slide Remove in at the card's trailing edge, or all the way to
/// remove in one gesture. The card makes room for it rather than sliding away, so
/// the name and set count are still there to check at the moment of removing. One
/// row is open at a time; scrolling, another swipe, or a tap closes it.
struct SwipeToRemove: ViewModifier {
    /// Grows with text size, so its label fits; past the cap, the label gives way to the icon alone.
    @ScaledMetric(relativeTo: .caption) private var scaledActionWidth: CGFloat = 88
    private var actionWidth: CGFloat { min(scaledActionWidth, 124) }

    let id: UUID
    @Binding var openID: UUID?
    var isEnabled = true
    let name: String
    let cornerRadius: CGFloat
    /// How far Remove sits inside the row's edge, such as inside a superset's outline.
    var inset: CGFloat = 0
    let remove: () -> Void
    @State private var translation: CGFloat = 0
    @State private var width: CGFloat = 0

    private var isOpen: Bool { openID == id }
    /// How much of the row Remove covers.
    private var reveal: CGFloat { max(0, (isOpen ? actionWidth : 0) - translation) }
    /// Past this, letting go removes the exercise rather than leaving Remove showing.
    private var isFullSwipe: Bool { reveal > max(actionWidth * 2, width * 0.6) }

    func body(content: Content) -> some View {
        content
            // The row makes room for Remove's own width; a longer swipe grows Remove over it.
            .environment(\.swipeRemoveReveal, min(reveal, actionWidth))
            .overlay {
                // Any tap on an open row closes it instead of reaching the row.
                if isOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .trailing) {
                if reveal > 0 { action.padding(inset) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(HorizontalSwipeGesture(isEnabled: isEnabled, allowsRight: isOpen) { change in
                switch change {
                case let .changed(x): translation = x
                case let .ended(velocity): end(velocity: velocity)
                case .cancelled: close()
                }
            })
            .sensoryFeedback(.impact(weight: .medium), trigger: isFullSwipe) { _, reached in reached }
            .onChange(of: isEnabled) { if !isEnabled { close() } }
    }

    private var action: some View {
        Button(action: removeNow) {
            // Laid out at Remove's full width, so the label doesn't pop in as the swipe opens it.
            ViewThatFits(in: .horizontal) {
                VStack(spacing: 3) {
                    trash
                    Text("Remove")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                trash
            }
            .foregroundStyle(AppTheme.onDestructive)
            .frame(width: max(0, actionWidth - inset * 2))
            .frame(width: max(0, min(reveal, width) - inset * 2))
            .frame(maxHeight: .infinity)
            .background(AppTheme.destructiveFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(name)")
        .accessibilityIdentifier("ReorderSwipeRemoveButton")
    }

    private func end(velocity: CGFloat) {
        if isFullSwipe {
            removeNow()
        } else if reveal > actionWidth / 2 || velocity < -600 {
            withAnimation(.snappy(duration: 0.25)) {
                translation = 0
                openID = id
            }
        } else {
            close()
        }
    }

    private var trash: some View {
        Image(systemName: "trash.fill").font(.callout.weight(.semibold))
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) {
            translation = 0
            if isOpen { openID = nil }
        }
    }

    private func removeNow() {
        translation = 0
        if isOpen { openID = nil }
        remove()
    }
}

/// A pan that only starts on a mostly horizontal swipe, so vertical drags still
/// scroll the list. It starts leftward only, unless its row is open.
private struct HorizontalSwipeGesture: UIGestureRecognizerRepresentable {
    enum Change {
        case changed(CGFloat)
        case ended(velocity: CGFloat)
        /// Interrupted, such as by a call: nothing is removed.
        case cancelled
    }

    let isEnabled: Bool
    let allowsRight: Bool
    let onChange: (Change) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.allowsRight = allowsRight
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed:
            onChange(.changed(recognizer.translation(in: recognizer.view).x))
        case .ended:
            onChange(.ended(velocity: recognizer.velocity(in: recognizer.view).x))
        case .cancelled, .failed:
            onChange(.cancelled)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true
        var allowsRight = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5 && (velocity.x < 0 || allowsRight)
        }

        /// The list's scrolling waits for this to decide, which it does on the first
        /// movement, so a quick sideways swipe isn't taken as a scroll.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}

extension EnvironmentValues {
    /// How much of a row its swiped Remove takes, so the row can make room for it.
    @Entry var swipeRemoveReveal: CGFloat = 0
}
