import SwiftUI
import UIKit

/// What a swiped row slides within.
enum SwipeToRemoveSurface {
    /// A card with its own surface. The whole card slides over the page, as in a
    /// system list.
    case card(cornerRadius: CGFloat)
    /// A row drawn on a container's fill, such as a superset member. Only its content
    /// slides, and Remove sits on the same fill, as when swiping a set. The inset keeps
    /// both inside the container's outline.
    case containerRow(inset: CGFloat)

    var clipShape: AnyShape {
        switch self {
        case let .card(cornerRadius): AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case let .containerRow(inset): AnyShape(Rectangle().inset(by: inset))
        }
    }
}

/// Swipe left to slide the row aside and show Remove behind it, or all the way to
/// remove in one gesture. One row is open at a time; scrolling, another swipe, or a
/// tap closes it.
struct SwipeToRemove: ViewModifier {
    /// The space the open row leaves for Remove. It grows with text size, up to a cap.
    @ScaledMetric(relativeTo: .footnote) private var scaledActionWidth: CGFloat = 76
    private var actionWidth: CGFloat { min(scaledActionWidth, 100) }
    @ScaledMetric(relativeTo: .body) private var scaledCapsuleHeight: CGFloat = 40
    /// Stops growing with text, as the system's swipe actions do; the action's text stops at accessibility1.
    private var capsuleHeight: CGFloat { min(scaledCapsuleHeight, 50) }

    let id: UUID
    @Binding var openID: UUID?
    var isEnabled = true
    let name: String
    let surface: SwipeToRemoveSurface
    let remove: () -> Void
    @State private var translation: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var isRemoving = false
    /// Once the row is off, Remove fades so the gap closes cleanly.
    @State private var hasCleared = false

    private var isOpen: Bool { openID == id }
    /// How far the row has slid aside.
    private var reveal: CGFloat {
        isRemoving ? width : max(0, (isOpen ? actionWidth : 0) - translation)
    }
    /// Past this, letting go removes the exercise rather than leaving Remove showing.
    private var isFullSwipe: Bool { isRemoving || reveal > max(actionWidth * 2, width * 0.6) }

    func body(content: Content) -> some View {
        content
            .overlay {
                // While any row is open, a tap on a row closes it instead of reaching the
                // row, as in a system list.
                if openID != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { closeAny() }
                        .accessibilityHidden(true)
                }
            }
            .offset(x: -reveal)
            .background(alignment: .trailing) {
                if reveal > 0 {
                    action.opacity(hasCleared ? 0 : 1)
                }
            }
            // Clipped only while it slides, so the card's own edge stays crisp at rest.
            .clipShape(reveal > 0 ? surface.clipShape : AnyShape(Rectangle().inset(by: -100)))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(HorizontalSwipeGesture(isEnabled: isEnabled && !isRemoving, allowsRight: isOpen) { change in
                switch change {
                case let .changed(x):
                    // Swiping another row closes the open one.
                    if let openID, openID != id { withAnimation(.snappy(duration: 0.25)) { self.openID = nil } }
                    translation = x
                case let .ended(velocity): end(velocity: velocity)
                case .cancelled: close()
                }
            })
            .sensoryFeedback(.impact(weight: .medium), trigger: isFullSwipe) { _, reached in reached }
            .animation(.snappy(duration: 0.22), value: isFullSwipe)
            .onChange(of: isEnabled) { if !isEnabled { close() } }
    }

    /// The system list's look: a red capsule with the trash icon, titled beneath. A full
    /// swipe stretches the capsule across the row, its icon following the row's edge.
    private var action: some View {
        Button(action: removeNow) {
            ViewThatFits(in: .horizontal) {
                VStack(spacing: 5) {
                    capsule
                    Text("Remove")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                capsule
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(width: isFullSwipe ? max(actionWidth, reveal) - 12 : actionWidth - 12)
            .frame(maxHeight: .infinity)
            .padding(.trailing, 6)
            .contentShape(Rectangle())
            // Grows in as the row uncovers it.
            .scaleEffect(0.6 + 0.4 * progress)
            .opacity(Double(progress))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(name)")
        .accessibilityIdentifier("ReorderSwipeRemoveButton")
    }

    private var progress: CGFloat { min(1, reveal / actionWidth) }

    private var capsule: some View {
        Image(systemName: "trash.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.onDestructive)
            .padding(.horizontal, isFullSwipe ? 18 : 0)
            .frame(maxWidth: .infinity, alignment: isFullSwipe ? .leading : .center)
            .frame(height: capsuleHeight)
            .background(AppTheme.destructive, in: Capsule())
            .frame(maxWidth: isFullSwipe ? .infinity : min(60, actionWidth - 12))
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

    private func closeAny() {
        withAnimation(.snappy(duration: 0.25)) { openID = nil }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) {
            translation = 0
            if isOpen { openID = nil }
        }
    }

    /// Slides the row the rest of the way off, then removes it.
    private func removeNow() {
        guard !isRemoving else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isRemoving = true
            translation = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.1)) { hasCleared = true }
            try? await Task.sleep(for: .milliseconds(100))
            if isOpen { openID = nil }
            remove()
        }
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
