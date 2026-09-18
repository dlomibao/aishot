// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aishot",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AIShotCore"),
        .executableTarget(name: "aishot", dependencies: ["AIShotCore"]),
        .testTarget(name: "AIShotCoreTests", dependencies: ["AIShotCore"]),
    ]
)
