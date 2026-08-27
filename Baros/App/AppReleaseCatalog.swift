import Foundation

enum WhatsNewSheetID: Equatable {
    case version1_0
    case version1_2
}

struct WhatsNewRelease: Equatable {
    let version: String
    let sheetID: WhatsNewSheetID
}

struct AppReleaseDefinition: Equatable {
    let version: String
    let whatsNewSheet: WhatsNewSheetID?

    var whatsNew: WhatsNewRelease? {
        guard let whatsNewSheet else {
            return nil
        }

        return WhatsNewRelease(
            version: version,
            sheetID: whatsNewSheet
        )
    }
}

enum AppReleaseCatalog {
    private static let releases = [
        AppReleaseDefinition(
            version: "1.0",
            whatsNewSheet: .version1_0
        ),
        AppReleaseDefinition(version: "1.1", whatsNewSheet: nil),
        AppReleaseDefinition(version: "1.2", whatsNewSheet: .version1_2),
    ]

    static func release(for version: String) -> AppReleaseDefinition? {
        releases.first { $0.version == version }
    }

    static func definition(for version: String) -> AppReleaseDefinition {
        release(for: version)
            ?? AppReleaseDefinition(version: version, whatsNewSheet: nil)
    }

    static func whatsNew(for version: String) -> WhatsNewRelease? {
        release(for: version)?.whatsNew
    }

    static func latestWhatsNew(upTo version: String) -> WhatsNewRelease? {
        guard let targetVersion = AppVersion(version) else {
            return nil
        }

        return releases.compactMap { release -> (version: AppVersion, whatsNew: WhatsNewRelease)? in
            guard let releaseVersion = AppVersion(release.version),
                  releaseVersion <= targetVersion,
                  let whatsNew = release.whatsNew else {
                return nil
            }

            return (version: releaseVersion, whatsNew: whatsNew)
        }
        .max { $0.version < $1.version }?
        .whatsNew
    }
}

private struct AppVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        let rawComponents = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !rawComponents.isEmpty else {
            return nil
        }

        var components: [Int] = []
        components.reserveCapacity(rawComponents.count)
        for rawComponent in rawComponents {
            guard !rawComponent.isEmpty,
                  rawComponent.allSatisfy(\.isNumber),
                  let component = Int(rawComponent) else {
                return nil
            }
            components.append(component)
        }

        while components.count > 1, components.last == 0 {
            components.removeLast()
        }
        self.components = components
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<componentCount {
            let lhsComponent = index < lhs.components.count ? lhs.components[index] : 0
            let rhsComponent = index < rhs.components.count ? rhs.components[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent < rhsComponent
            }
        }

        return false
    }
}
