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
        guard let currentIndex = releases.firstIndex(where: { $0.version == version }) else {
            return nil
        }

        return releases[...currentIndex].reversed().compactMap(\.whatsNew).first
    }
}
