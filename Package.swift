// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Starlist",
    platforms: [.macOS(.v15)],
    targets: [
        // Everything testable: the task store, Markdown archives, and the SwiftUI views.
        .target(
            name: "StarlistKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu bar app itself: status item, panel, menus.
        .executableTarget(
            name: "Starlist",
            dependencies: ["StarlistKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Build-time helper: renders the app icon, UI snapshots, and runs logic checks.
        .executableTarget(
            name: "starlist-dev",
            dependencies: ["StarlistKit"],
            path: "Sources/StarlistDev",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
