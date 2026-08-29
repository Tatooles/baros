import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable {
    case dark
    case light
    case system

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark:
            .dark
        case .light:
            .light
        case .system:
            nil
        }
    }

    var displayName: String {
        switch self {
        case .dark:
            "Dark"
        case .light:
            "Light"
        case .system:
            "System"
        }
    }

    var systemImage: String {
        switch self {
        case .dark:
            "moon.fill"
        case .light:
            "sun.max.fill"
        case .system:
            "circle.lefthalf.filled"
        }
    }
}

@MainActor
@Observable
final class AppAppearancePreferenceStore {
    private static let standardKey = "Baros.AppAppearance.preference"

    private let defaults: UserDefaults
    private let key: String

    var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: key)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        key: String = AppAppearancePreferenceStore.standardKey
    ) {
        self.defaults = defaults
        self.key = key
        appearance = defaults.string(forKey: key).flatMap(AppAppearance.init(rawValue:)) ?? .dark
    }

    static func resetForUITestingIfRequested(
        arguments: [String],
        defaults: UserDefaults = .standard,
        key: String = standardKey
    ) {
        guard arguments.contains("--uitest-reset-app-appearance") else {
            return
        }

        defaults.removeObject(forKey: key)
    }
}
