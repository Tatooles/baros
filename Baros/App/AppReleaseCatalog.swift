import Foundation

struct WhatsNewRelease: Equatable {
    let version: String
    let title: String
    let summary: String
    let items: [LaunchExperienceItem]
}

struct LaunchExperienceItem: Identifiable, Equatable {
    let id: String
    let systemImage: String
    let title: String
    let detail: String
}

struct WhatsNewContent: Equatable {
    let title: String
    let summary: String
    let items: [LaunchExperienceItem]
}

struct AppReleaseDefinition: Equatable {
    let version: String
    let whatsNewContent: WhatsNewContent?

    var whatsNew: WhatsNewRelease? {
        guard let whatsNewContent else {
            return nil
        }

        return WhatsNewRelease(
            version: version,
            title: whatsNewContent.title,
            summary: whatsNewContent.summary,
            items: whatsNewContent.items
        )
    }
}

enum AppReleaseCatalog {
    private static let releases = [
        AppReleaseDefinition(
            version: "1.0",
            whatsNewContent: WhatsNewContent(
                title: "What's new in Baros",
                summary: "The first release of Baros: fast workout logging, a safe local history, and optional cloud sync.",
                items: [
                    LaunchExperienceItem(
                        id: "offline-first",
                        systemImage: "iphone",
                        title: "Offline-first logging",
                        detail: "Start and finish workouts even when the network is unavailable."
                    ),
                    LaunchExperienceItem(
                        id: "cloud-sync",
                        systemImage: "icloud",
                        title: "Cloud sync",
                        detail: "Sign in to sync completed workouts, exercises, and settings."
                    ),
                    LaunchExperienceItem(
                        id: "data-controls",
                        systemImage: "square.and.arrow.up",
                        title: "Data controls",
                        detail: "Export workout history and manage privacy from Settings."
                    ),
                ]
            )
        ),
        AppReleaseDefinition(version: "1.1", whatsNewContent: nil),
    ]

    static func release(for version: String) -> AppReleaseDefinition? {
        releases.first { $0.version == version }
    }

    static func definition(for version: String) -> AppReleaseDefinition {
        release(for: version)
            ?? AppReleaseDefinition(version: version, whatsNewContent: nil)
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
