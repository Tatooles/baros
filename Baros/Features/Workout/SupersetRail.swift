import SwiftUI

/// A superset's members under a "SUPERSET · N" label, with a thin accent rail
/// in the page margin beside them. The members keep their own look and width.
struct SupersetRail<Content: View>: View {
    static var railWidth: CGFloat { 4 }
    static var railSpacing: CGFloat { 6 }
    /// How far the rail reaches into the leading margin.
    static var marginWidth: CGFloat { railWidth + railSpacing }

    let count: Int
    var spacing: CGFloat = 8
    /// Off where the leading margin holds other controls, such as edit-mode lists.
    var reachesIntoMargin = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SupersetLabel(count: count)
                .padding(.leading, 12)
            HStack(spacing: Self.railSpacing) {
                Capsule()
                    .fill(AppTheme.brandAccentForeground)
                    .frame(width: Self.railWidth)
                    .accessibilityHidden(true)
                VStack(spacing: spacing) { content }
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
