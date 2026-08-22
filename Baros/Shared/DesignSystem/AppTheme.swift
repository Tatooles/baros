import SwiftUI
import UIKit

enum AppTheme {
    // MARK: Backgrounds

    static let appCanvas = dynamicColor(
        light: uiColor(0xF7F6F3),
        dark: uiColor(0x000000)
    )
    static let groupedSurface = dynamicColor(
        light: uiColor(0xFFFFFF),
        dark: uiColor(0x1C1C1E)
    )
    static let recessedSurface = dynamicColor(
        light: uiColor(0xF2F2F4),
        dark: uiColor(0x242426)
    )
    static let fieldSurface = dynamicColor(
        light: uiColor(0xECECF0),
        dark: uiColor(0x2C2C2E)
    )
    static let subtleBorder = dynamicColor(
        light: uiColor(0x09121D, alpha: 0.09),
        dark: uiColor(0xFFFFFF, alpha: 0.11)
    )
    static let surfaceShadow = dynamicColor(
        light: uiColor(0x000000, alpha: 0.07),
        dark: uiColor(0x000000, alpha: 0.18)
    )

    static let focusSurface = LinearGradient(
        colors: [
            dynamicColor(light: uiColor(0xFFFFFF), dark: uiColor(0x0A0C10)),
            dynamicColor(light: uiColor(0xFAFAFA), dark: uiColor(0x050608)),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let canvasBackground = appCanvas

    // MARK: Accent

    static let brandAccentFill = BarosBrand.cobalt
    static let brandAccentForeground = BarosBrand.accentForeground
    static let brandAccentMuted = BarosBrand.accentMuted
    static let brandFocus = brandAccentForeground
    static let brandAccentGlow = BarosBrand.accentGlow
    static let destructive = Color(.systemRed)
    static let destructiveForeground = dynamicColor(
        light: uiColor(0xB42318),
        dark: uiColor(0xFF6961)
    )
    static let success = Color(.systemGreen)
    static let successForeground = dynamicColor(
        light: uiColor(0x1B6E2A),
        dark: uiColor(0x4CD964)
    )

    /// Foreground for content sitting on `brandAccentFill` or
    /// `brandAccentGradient`.
    static let onBrandAccent = BarosBrand.onAccent
    static let onDestructive = Color.white

    // MARK: Text

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let brandAccentGradient = LinearGradient(
        colors: [Color(uiColor(0x1C66C7)), Color(uiColor(0x1768E5))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
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

    private static func uiColor(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
