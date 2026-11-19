import Foundation

public enum ConvexConfiguration {
    static let deploymentURL = AppEnvironmentConfiguration.current.convexDeploymentURL

    public static var deploymentURLString: String {
        deploymentURL.absoluteString
    }
}
