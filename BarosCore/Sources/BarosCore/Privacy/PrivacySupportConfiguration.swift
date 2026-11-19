import Foundation

public struct PrivacySupportConfiguration: Equatable, Sendable {
    public let privacyPolicyURL: URL
    public let supportURL: URL

    public static let release = PrivacySupportConfiguration(
        privacyPolicyURL: URL(string: "https://baros.fit/privacy")!,
        supportURL: URL(string: "https://baros.fit/support")!
    )
}
