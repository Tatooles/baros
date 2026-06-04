import Foundation

enum ConvexConfiguration {
    static let deploymentURL = URL(string: "https://glad-cow-603.convex.cloud")!

    static var deploymentURLString: String {
        deploymentURL.absoluteString
    }
}
