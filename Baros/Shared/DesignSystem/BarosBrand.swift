import SwiftUI
import UIKit

enum BarosBrand {
    static let cobalt = dynamicColor(
        light: uiColor(0x1C66C7),
        dark: uiColor(0x1768E5)
    )
    static let blueBlack = dynamicColor(
        light: uiColor(0x09121D),
        dark: uiColor(0x080A0D)
    )
    static let foreground = dynamicColor(
        light: uiColor(0xF3EBE7),
        dark: uiColor(0xF7F7F5)
    )
    static let accentForeground = dynamicColor(
        light: uiColor(0x1C66C7),
        dark: uiColor(0x4D94FF)
    )
    static let accentMuted = dynamicColor(
        light: uiColor(0x1C66C7, alpha: 0.08),
        dark: uiColor(0x1768E5, alpha: 0.16)
    )
    static let accentGlow = dynamicColor(
        light: uiColor(0x1C66C7, alpha: 0.24),
        dark: uiColor(0x1768E5, alpha: 0.28)
    )
    static let onAccent = Color.white

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
