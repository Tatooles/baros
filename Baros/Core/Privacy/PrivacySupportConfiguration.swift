import Foundation

struct PrivacySupportConfiguration: Equatable {
    let privacyPolicyURL: URL
    let supportURL: URL

    static let release = PrivacySupportConfiguration(
        privacyPolicyURL: URL(string: "https://baros.fit/privacy")!,
        supportURL: URL(string: "https://baros.fit/support")!
    )
}
