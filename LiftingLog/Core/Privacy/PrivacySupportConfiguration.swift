import Foundation

struct PrivacySupportConfiguration: Equatable {
    let privacyPolicyURL: URL?
    let supportURL: URL?
    let unavailableDetailText: String

    static let release = PrivacySupportConfiguration(
        privacyPolicyURL: URL(string: "https://support.liftinglog.app/privacy"),
        supportURL: URL(string: "https://support.liftinglog.app/"),
        unavailableDetailText: "Available before release"
    )

    static let issue13Development = PrivacySupportConfiguration(
        privacyPolicyURL: nil,
        supportURL: nil,
        unavailableDetailText: "Available before release"
    )
}
