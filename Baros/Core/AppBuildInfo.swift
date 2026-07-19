import Foundation
import UIKit

struct DeviceSystemInfo: Equatable {
    let model: String
    let systemName: String
    let systemVersion: String

    @MainActor
    static var current: DeviceSystemInfo {
        let device = UIDevice.current
        return DeviceSystemInfo(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion
        )
    }
}

struct AppBuildInfo: Equatable {
    let displayName: String
    let bundleIdentifier: String
    let version: String
    let buildNumber: String
    let environmentName: String
    let sourceMetadata: AppSourceMetadata?

    init(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        sourceMetadata: AppSourceMetadata? = AppSourceMetadata.current
    ) {
        self.displayName = Self.stringValue(
            forKey: "CFBundleDisplayName",
            in: infoDictionary,
            fallback: "Baros"
        )
        self.bundleIdentifier = Self.stringValue(
            forKey: "CFBundleIdentifier",
            in: infoDictionary,
            fallback: "Unknown"
        )
        self.version = Self.stringValue(
            forKey: "CFBundleShortVersionString",
            in: infoDictionary,
            fallback: "Unknown"
        )
        self.buildNumber = Self.stringValue(
            forKey: "CFBundleVersion",
            in: infoDictionary,
            fallback: "Unknown"
        )
        self.environmentName = Self.stringValue(
            forKey: "BarosEnvironment",
            in: infoDictionary,
            fallback: "Unknown"
        )
        self.sourceMetadata = sourceMetadata
    }

    static let current = AppBuildInfo()

    var versionAndBuild: String {
        "\(version) (\(buildNumber))"
    }

    var settingsVersionText: String {
        "Version \(versionAndBuild)"
    }

    func supportSummary(device: DeviceSystemInfo) -> String {
        """
        App: \(displayName)
        Version: \(versionAndBuild)
        Environment: \(environmentName)
        Bundle ID: \(bundleIdentifier)
        Device: \(device.model)
        OS: \(device.systemName) \(device.systemVersion)
        """
    }

    private static func stringValue(forKey key: String, in infoDictionary: [String: Any], fallback: String) -> String {
        guard let value = infoDictionary[key] as? String, !value.isEmpty else {
            return fallback
        }
        return value
    }
}

struct AppSourceMetadata: Equatable {
    let branch: String
    let shortCommit: String
    let hasLocalChanges: Bool
    let builtAt: String
    let configuration: String

    init(
        branch: String,
        shortCommit: String,
        hasLocalChanges: Bool,
        builtAt: String,
        configuration: String
    ) {
        self.branch = branch
        self.shortCommit = shortCommit
        self.hasLocalChanges = hasLocalChanges
        self.builtAt = builtAt
        self.configuration = configuration
    }

    init?(plistDictionary: [String: Any]) {
        self.init(
            branch: Self.stringValue(forKey: "Branch", in: plistDictionary),
            shortCommit: Self.stringValue(forKey: "ShortCommit", in: plistDictionary),
            hasLocalChanges: plistDictionary["HasLocalChanges"] as? Bool ?? false,
            builtAt: Self.stringValue(forKey: "BuiltAt", in: plistDictionary),
            configuration: Self.stringValue(forKey: "Configuration", in: plistDictionary)
        )
    }

    static var current: AppSourceMetadata? {
        guard
            let url = Bundle.main.url(forResource: "BuildSourceMetadata", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = propertyList as? [String: Any]
        else {
            return nil
        }

        return AppSourceMetadata(plistDictionary: dictionary)
    }

    var branchDisplay: String {
        normalized(branch, fallback: "Unknown")
    }

    var builtAtDisplay: String {
        normalized(builtAt, fallback: "Unknown")
    }

    var configurationDisplay: String {
        normalized(configuration, fallback: "Unknown")
    }

    var sourceDescription: String {
        var description = branchDisplay
        let commit = normalized(shortCommit)

        if !commit.isEmpty {
            description += " @ \(commit)"
        }

        if hasLocalChanges {
            description += " + local changes"
        }

        return description
    }

    private static func stringValue(forKey key: String, in dictionary: [String: Any]) -> String {
        dictionary[key] as? String ?? ""
    }

    private func normalized(_ value: String, fallback: String = "") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
