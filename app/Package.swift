// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PRStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PRCore"),
        .executableTarget(name: "PRStatus", dependencies: ["PRCore"]),
    ],
    swiftLanguageModes: [.v5]
)
