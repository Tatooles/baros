import Foundation

struct PrivacySupportConfiguration: Equatable {
    let privacyPolicyURL: URL?
    let supportURL: URL?
    let unavailableDetailText: String

    static let release = PrivacySupportConfiguration(
        privacyPolicyURL: URL(string: "https://baros.fit/privacy"),
        supportURL: URL(string: "https://baros.fit/support"),
        unavailableDetailText: "Available before release"
    )

    static let issue13Development = PrivacySupportConfiguration(
        privacyPolicyURL: nil,
        supportURL: nil,
        unavailableDetailText: "Available before release"
    )
}
