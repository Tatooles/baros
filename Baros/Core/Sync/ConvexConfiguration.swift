import Foundation

enum ConvexConfiguration {
    static let deploymentURL = AppEnvironmentConfiguration.current.convexDeploymentURL

    static var deploymentURLString: String {
        deploymentURL.absoluteString
    }
}
