import SwiftUI

/// Reveals a trailing delete action when the row is swiped left, mirroring
/// `List` swipe actions — including full-swipe-to-delete with a threshold
/// haptic — for rows hosted in a plain `ScrollView`.
struct SwipeToDeleteRow<Content: View>: View {
    let deleteAccessibilityLabel: String
    var deleteAccessibilityIdentifier: String?
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false
    @State private var lockedAxis: Axis?
    @State private var rowWidth: CGFloat = 0
    @State private var isArmedForFullSwipe = false

    private let revealWidth: CGFloat = 72
    /// Dragging past this fraction of the row width commits the delete, like a
    /// full swipe in `List`.
    private let fullSwipeFraction: CGFloat = 0.5
    private let deleteShape = RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)

    var body: some View {
        content
            .offset(x: offsetX)
            .background(alignment: .trailing) {
                // The red area grows to exactly fill whatever the row has
                // revealed, flush against the sliding content, like a List
                // swipe action.
                if offsetX < -1 {
                    Button(role: .destructive, action: performDelete) {
                        deleteShape
                            .fill(Color(.systemRed))
                            .overlay(
                                Image(systemName: "trash.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .opacity(min(1, (-offsetX - 24) / 24))
                            )
                            .frame(width: max(0, -offsetX - 8))
                            .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(deleteAccessibilityLabel)
                    .accessibilityIdentifier(deleteAccessibilityIdentifier ?? deleteAccessibilityLabel)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { rowWidth = $0 }
            .contentShape(Rectangle())
            .onTapGesture { if isOpen { close() } }
            .simultaneousGesture(dragGesture)
            // Native haptic when the swipe crosses the full-swipe threshold,
            // matching Mail/Messages. Fires only on the false→true transition,
            // so it re-arms if you pull back out and cross again, and stays
            // silent for a button tap.
            .sensoryFeedback(trigger: isArmedForFullSwipe) { _, armed in
                armed ? .impact(weight: .medium) : nil
            }
            .accessibilityAction(named: deleteAccessibilityLabel, performDelete)
    }

    private var dragGesture: some Gesture {
        // A higher minimum distance lets the enclosing scroll view win the
        // recognition race for vertical drags — especially when a drag starts
        // on a text field — before this horizontal swipe engages.
        DragGesture(minimumDistance: 22)
            .onChanged { value in
                // Lock to the dominant axis once per drag; vertical drags stay
                // with the enclosing scroll view.
                if lockedAxis == nil {
                    lockedAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard lockedAxis == .horizontal else { return }

                let proposed = restingOffset + value.translation.width
                // Resist swiping right past the resting position.
                offsetX = proposed > 0 ? proposed / 6 : proposed
                isArmedForFullSwipe = isPastFullSwipe(proposed)
            }
            .onEnded { value in
                defer {
                    lockedAxis = nil
                    isArmedForFullSwipe = false
                }
                guard lockedAxis == .horizontal else { return }

                // Actual distance commits the delete; a quick flick only reveals
                // the button (so a fast short flick never deletes).
                if isPastFullSwipe(restingOffset + value.translation.width) {
                    withAnimation(slideAnimation) { offsetX = -rowWidth }
                    performDelete()
                } else {
                    setOpen(restingOffset + value.predictedEndTranslation.width < -revealWidth * 0.5)
                }
            }
    }

    private var restingOffset: CGFloat { isOpen ? -revealWidth : 0 }

    private func isPastFullSwipe(_ offset: CGFloat) -> Bool {
        rowWidth > 0 && offset < -rowWidth * fullSwipeFraction
    }

    private func setOpen(_ open: Bool) {
        withAnimation(slideAnimation) {
            offsetX = open ? -revealWidth : 0
            isOpen = open
        }
    }

    private func close() { setOpen(false) }

    private func performDelete() {
        withAnimation(slideAnimation) { onDelete() }
    }

    private let slideAnimation = Animation.spring(response: 0.3, dampingFraction: 0.85)
}
