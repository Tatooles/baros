import SwiftUI
import UIKit

enum BarosBrand {
    static let brandCobalt = BarosAdaptiveColor.dynamic(
        light: 0x1C66C7,
        dark: 0x1768E5
    )
    static let brandBlueBlack = BarosAdaptiveColor.dynamic(
        light: 0x09121D,
        dark: 0x080A0D
    )
    static let brandForeground = BarosAdaptiveColor.dynamic(
        light: 0xF3EBE7,
        dark: 0xF7F7F5
    )
    static let brandAccentForeground = BarosAdaptiveColor.dynamic(
        light: 0x1C66C7,
        dark: 0x4D94FF
    )
    static let brandAccentMuted = BarosAdaptiveColor.dynamic(
        light: 0x1C66C7,
        lightAlpha: 0.08,
        dark: 0x1768E5,
        darkAlpha: 0.16
    )
    static let brandAccentGlow = BarosAdaptiveColor.dynamic(
        light: 0x1C66C7,
        lightAlpha: 0.24,
        dark: 0x1768E5,
        darkAlpha: 0.28
    )
    static let onBrandAccent = Color.white
}

enum BarosAdaptiveColor {
    static func dynamic(
        light: UInt32,
        lightAlpha: CGFloat = 1,
        dark: UInt32,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? uiColor(dark, alpha: darkAlpha)
                : uiColor(light, alpha: lightAlpha)
        })
    }

    static func fixed(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor(hex, alpha: alpha))
    }

    private static func uiColor(_ hex: UInt32, alpha: CGFloat) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
