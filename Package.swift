// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Awning",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic (file I/O, sync/merge decisions, text transforms) — unit tested.
        .target(name: "AwningCore"),
        // The AppKit app.
        .executableTarget(name: "Awning", dependencies: ["AwningCore"]),
        .testTarget(name: "AwningCoreTests", dependencies: ["AwningCore"]),
    ]
)
