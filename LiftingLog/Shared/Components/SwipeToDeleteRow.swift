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

    private let revealWidth: CGFloat = 72
    private let deleteShape = RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)

    var body: some View {
        content
            .offset(x: offsetX)
            .background(alignment: .trailing) {
                if offsetX < -1 {
                    Button(role: .destructive) {
                        performDelete()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: revealWidth - 10)
                            .frame(maxHeight: .infinity)
                            .background(Color(.systemRed), in: deleteShape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(deleteAccessibilityLabel)
                    .accessibilityIdentifier(deleteAccessibilityIdentifier ?? deleteAccessibilityLabel)
                    .transition(.opacity)
                }
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
                        let projected = base + value.predictedEndTranslation.width
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            if projected < -revealWidth * 0.6 {
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
