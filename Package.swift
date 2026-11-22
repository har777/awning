// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickNotes",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic (file I/O, sync/merge decisions, text transforms) — unit tested.
        .target(name: "QuickNotesCore"),
        // The AppKit app.
        .executableTarget(name: "QuickNotes", dependencies: ["QuickNotesCore"]),
        .testTarget(name: "QuickNotesCoreTests", dependencies: ["QuickNotesCore"]),
    ]
)
