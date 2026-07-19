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
            // Clip so collapsing content is swallowed by the card edge
            // instead of sliding over it.
            .clipShape(shape)
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

struct MetricSummaryCard: View {
    let title: String
    let value: String
    var minimumScaleFactor: CGFloat = 0.7

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .minimumScaleFactor(minimumScaleFactor)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            AppTheme.surfaceMuted,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}
