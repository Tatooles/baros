// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BarosCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "BarosCore", targets: ["BarosCore"]),
    ],
    targets: [
        .target(name: "BarosCore"),
        .testTarget(name: "BarosCoreTests", dependencies: ["BarosCore"]),
    ],
    swiftLanguageModes: [.v6]
)
