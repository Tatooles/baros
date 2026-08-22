import SwiftUI
import UIKit

enum AppTheme {
    // MARK: Backgrounds

    static let appCanvas = BarosAdaptiveColor.dynamic(
        light: 0xF7F6F3,
        dark: 0x000000
    )
    static let groupedSurface = BarosAdaptiveColor.dynamic(
        light: 0xFFFFFF,
        dark: 0x1C1C1E
    )
    static let recessedSurface = BarosAdaptiveColor.dynamic(
        light: 0xF2F2F4,
        dark: 0x242426
    )
    static let fieldSurface = BarosAdaptiveColor.dynamic(
        light: 0xECECF0,
        dark: 0x2C2C2E
    )
    static let subtleBorder = BarosAdaptiveColor.dynamic(
        light: 0x09121D,
        lightAlpha: 0.09,
        dark: 0xFFFFFF,
        darkAlpha: 0.11
    )
    static let surfaceShadow = BarosAdaptiveColor.dynamic(
        light: 0x000000,
        lightAlpha: 0.07,
        dark: 0x000000,
        darkAlpha: 0.18
    )

    static let focusSurface = LinearGradient(
        colors: [
            BarosAdaptiveColor.dynamic(light: 0xFFFFFF, dark: 0x0A0C10),
            BarosAdaptiveColor.dynamic(light: 0xFAFAFA, dark: 0x050608),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let canvasBackground = appCanvas

    // MARK: Accent

    static let brandAccentFill = BarosBrand.brandCobalt
    static let brandAccentForeground = BarosBrand.brandAccentForeground
    static let brandAccentMuted = BarosBrand.brandAccentMuted
    static let brandFocus = brandAccentForeground
    static let brandAccentGlow = BarosBrand.brandAccentGlow
    static let destructive = Color(.systemRed)
    static let destructiveForeground = BarosAdaptiveColor.dynamic(
        light: 0xB42318,
        dark: 0xFF6961
    )
    static let success = Color(.systemGreen)
    static let successForeground = BarosAdaptiveColor.dynamic(
        light: 0x1B6E2A,
        dark: 0x4CD964
    )

    /// Foreground for content sitting on `brandAccentFill` or
    /// `brandAccentGradient`.
    static let onBrandAccent = BarosBrand.onBrandAccent
    static let onDestructive = Color.white

    // MARK: Text

    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let brandAccentGradient = LinearGradient(
        colors: [
            BarosAdaptiveColor.fixed(0x1C66C7),
            BarosAdaptiveColor.fixed(0x1768E5),
        ],
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

}
