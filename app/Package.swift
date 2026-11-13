// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubRadar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PRCore"),
        .executableTarget(name: "GitHubRadar", dependencies: ["PRCore"]),
    ],
    swiftLanguageModes: [.v5]
)
