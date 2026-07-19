import SwiftUI
import UIKit

enum AppTheme {
    // MARK: Backgrounds

    static let background = dynamicColor(
        light: UIColor(red: 0.949, green: 0.945, blue: 0.941, alpha: 1),
        dark: UIColor(red: 0.051, green: 0.051, blue: 0.055, alpha: 1)
    )
    static let backgroundTop = dynamicColor(
        light: UIColor(red: 0.973, green: 0.965, blue: 0.957, alpha: 1),
        dark: UIColor(red: 0.094, green: 0.090, blue: 0.094, alpha: 1)
    )

    /// Opaque surface for contexts where glass/material isn't appropriate.
    static let surface = Color(.secondarySystemGroupedBackground)
    /// Recessed fill for grouped content inside a card.
    static let surfaceMuted = Color(.tertiarySystemFill)
    /// Recessed fill for input fields inside a card.
    static let surfaceStrong = Color(.quaternarySystemFill)
    /// Fill for editable fields inside a card — stronger than surfaceMuted so
    /// inputs read as the primary content.
    static let fieldFill = Color(.secondarySystemFill)

    static let border = Color(.separator).opacity(0.5)
    static let borderStrong = Color(.separator)

    // MARK: Accent

    static let accent = dynamicColor(
        light: UIColor(red: 0.753, green: 0.224, blue: 0.169, alpha: 1),
        dark: UIColor(red: 0.753, green: 0.224, blue: 0.169, alpha: 1)
    )
    static let accentBright = dynamicColor(
        light: UIColor(red: 0.835, green: 0.247, blue: 0.188, alpha: 1),
        dark: UIColor(red: 0.910, green: 0.298, blue: 0.239, alpha: 1)
    )
    static let accentMuted = accent.opacity(0.18)
    static let accentGlow = accent.opacity(0.34)
    static let success = Color(.systemGreen)

    /// Foreground for content sitting on `accent`/`accentGradient` fills. Fixed
    /// white rather than the adaptive label color, since the accent red reads
    /// well with white in both light and dark appearance.
    static let onAccent = Color.white

    // MARK: Text

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let accentGradient = LinearGradient(
        colors: [accent, accentBright],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Soft page background that content floats above.
    static let subtleBackground = LinearGradient(
        colors: [backgroundTop, background],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Metrics

    static let cardCornerRadius: CGFloat = 26
    static let fieldCornerRadius: CGFloat = 14
    static let shellPadding: CGFloat = 16

    static func formatDuration(_ seconds: Int) -> String {
        WorkoutFormatters.duration(seconds)
    }

    static func formatDate(_ date: Date) -> String {
        WorkoutFormatters.date(date)
    }

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
