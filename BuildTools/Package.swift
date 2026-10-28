// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "GlanceBuildTools",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.63.1")
    ],
    targets: [.target(name: "GlanceBuildTools", path: "Sources")]
)
