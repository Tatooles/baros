import SwiftUI

enum SurfaceCardRole {
    case grouped
    case focus

    var backgroundStyle: AnyShapeStyle {
        switch self {
        case .grouped:
            AnyShapeStyle(AppTheme.groupedSurface)
        case .focus:
            AnyShapeStyle(AppTheme.focusSurface)
        }
    }
}

struct SurfaceCard<Content: View>: View {
    let role: SurfaceCardRole
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(
        role: SurfaceCardRole = .grouped,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
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
            .background(role.backgroundStyle, in: shape)
            // Clip so collapsing content is swallowed by the card edge
            // instead of sliding over it.
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
            )
            .shadow(
                color: AppTheme.surfaceShadow,
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
            AppTheme.recessedSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}
