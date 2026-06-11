// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkdownViewer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "MarkdownViewerCore",
            dependencies: ["Ink"]
        ),
        .executableTarget(
            name: "MarkdownViewer",
            dependencies: ["MarkdownViewerCore"]
        ),
        .executableTarget(
            name: "QuickLookPreview",
            dependencies: ["MarkdownViewerCore"],
            linkerSettings: [
                // App extension binaries enter through NSExtensionMain, not main
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(
            name: "MarkdownViewerCoreTests",
            dependencies: ["MarkdownViewerCore"]
        ),
    ]
)
