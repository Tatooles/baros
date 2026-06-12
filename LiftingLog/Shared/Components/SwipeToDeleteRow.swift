import SwiftUI

/// Reveals a trailing delete action when the row is swiped left, mirroring
/// `List` swipe actions for rows hosted in a plain `ScrollView`.
struct SwipeToDeleteRow<Content: View>: View {
    let deleteAccessibilityLabel: String
    var deleteAccessibilityIdentifier: String?
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false
    @State private var lockedAxis: Axis?
    @State private var rowWidth: CGFloat = 0

    private let revealWidth: CGFloat = 72
    /// Dragging past this fraction of the row width commits the delete
    /// directly on release, like a full swipe in List.
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
                    Button(role: .destructive) {
                        performDelete()
                    } label: {
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
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                rowWidth = width
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isOpen {
                    close()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        // Decide once per drag whether it is a horizontal swipe;
                        // vertical drags stay with the enclosing scroll view.
                        if lockedAxis == nil {
                            lockedAxis = abs(value.translation.width) > abs(value.translation.height)
                                ? .horizontal
                                : .vertical
                        }
                        guard lockedAxis == .horizontal else { return }

                        let base: CGFloat = isOpen ? -revealWidth : 0
                        let proposed = base + value.translation.width
                        // Resist swiping right past the resting position.
                        offsetX = proposed > 0 ? proposed / 6 : proposed
                    }
                    .onEnded { value in
                        defer { lockedAxis = nil }
                        guard lockedAxis == .horizontal else { return }

                        let base: CGFloat = isOpen ? -revealWidth : 0
                        let dragged = base + value.translation.width
                        let projected = base + value.predictedEndTranslation.width

                        // Actual distance (not flick projection) commits the
                        // delete, so a quick flick only reveals the button.
                        if rowWidth > 0, dragged < -rowWidth * fullSwipeFraction {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                offsetX = -rowWidth
                            }
                            performDelete()
                            return
                        }

                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            if projected < -revealWidth * 0.5 {
                                offsetX = -revealWidth
                                isOpen = true
                            } else {
                                offsetX = 0
                                isOpen = false
                            }
                        }
                    }
            )
            .accessibilityAction(named: deleteAccessibilityLabel) {
                performDelete()
            }
    }

    private func performDelete() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            onDelete()
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offsetX = 0
            isOpen = false
        }
    }
}
