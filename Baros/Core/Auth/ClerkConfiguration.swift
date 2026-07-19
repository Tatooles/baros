import Foundation

enum BarosEnvironment: String {
    case development = "Development"
    case production = "Production"
}

struct AppEnvironmentConfiguration: Equatable {
    let environment: BarosEnvironment
    let clerkPublishableKey: String
    let clerkAssociatedDomain: String
    let convexDeploymentURL: URL

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.environment = BarosEnvironment(
            rawValue: AppEnvironmentConfiguration.requiredString(
                forKey: "BarosEnvironment",
                in: infoDictionary
            )
        ) ?? .development
        self.clerkPublishableKey = AppEnvironmentConfiguration.requiredString(
            forKey: "ClerkPublishableKey",
            in: infoDictionary
        )
        self.clerkAssociatedDomain = AppEnvironmentConfiguration.requiredString(
            forKey: "ClerkAssociatedDomain",
            in: infoDictionary
        )

        let deploymentURLString = AppEnvironmentConfiguration.requiredString(
            forKey: "ConvexDeploymentURL",
            in: infoDictionary
        )
        guard let deploymentURL = URL(string: deploymentURLString) else {
            preconditionFailure("Invalid ConvexDeploymentURL: \(deploymentURLString)")
        }
        self.convexDeploymentURL = deploymentURL
    }

    static let current = AppEnvironmentConfiguration()

    private static func requiredString(forKey key: String, in infoDictionary: [String: Any]) -> String {
        guard let value = infoDictionary[key] as? String, !value.isEmpty else {
            preconditionFailure("Missing required Info.plist value: \(key)")
        }
        return value
    }
}

enum ClerkConfiguration {
    static let publishableKey = AppEnvironmentConfiguration.current.clerkPublishableKey
    static let associatedDomain = AppEnvironmentConfiguration.current.clerkAssociatedDomain
}
