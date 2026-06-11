import SwiftUI

struct SurfaceCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: shape)
            .overlay(
                shape.strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                    lineWidth: 1
                )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.3 : 0.07),
                radius: 14,
                y: 5
            )
            .containerShape(shape)
    }
}
