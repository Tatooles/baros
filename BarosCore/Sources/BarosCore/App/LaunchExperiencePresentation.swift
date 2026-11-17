import Foundation

public enum LaunchExperiencePresentation: Identifiable, Equatable {
    case onboarding
    case whatsNew(WhatsNewRelease)

    public var id: String {
        switch self {
        case .onboarding:
            "onboarding"
        case .whatsNew(let release):
            "whats-new-\(release.version)"
        }
    }
}
