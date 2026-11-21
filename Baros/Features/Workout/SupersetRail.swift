import SwiftUI

struct SupersetRail<Content: View>: View {
    static var railWidth: CGFloat { 4 }
    static var railSpacing: CGFloat { 6 }
    static var marginWidth: CGFloat { railWidth + railSpacing }
    static var labelSpacing: CGFloat { 6 }

    let count: Int
    var spacing: CGFloat = 8
    var reachesIntoMargin = true
    var balancesLabel = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Self.labelSpacing) {
            SupersetLabel(count: count)
                .padding(.leading, 12)
            VStack(spacing: spacing) { content }
                .padding(.leading, Self.railWidth + Self.railSpacing)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.brandAccentForeground)
                        .frame(width: Self.railWidth)
                        .accessibilityHidden(true)
                }
            if balancesLabel {
                SupersetLabel(count: count)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, reachesIntoMargin ? -Self.marginWidth : 0)
        .accessibilityElement(children: .contain)
    }
}

struct SupersetLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
            Text("SUPERSET")
                .tracking(1.2)
            Text("· \(count)")
                .foregroundStyle(AppTheme.brandAccentForeground.opacity(0.7))
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(AppTheme.brandAccentForeground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Superset of \(count) exercises")
        .accessibilityIdentifier("SupersetLabel")
    }
}
