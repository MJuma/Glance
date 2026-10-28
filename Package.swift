// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "GlanceMonitor", targets: ["GlanceMonitor"]),
        .executable(name: "GlanceTime", targets: ["GlanceTime"])
    ],
    targets: [
        .target(
            name: "GlancePlatform",
            path: "Platform",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "GlanceSupport",
            path: "Shared",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "GlanceMonitor",
            dependencies: ["GlanceSupport", "GlancePlatform"],
            path: "Apps/GlanceMonitor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "GlanceTime",
            dependencies: ["GlanceSupport"],
            path: "Apps/GlanceTime",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "GlanceSupportTests",
            dependencies: ["GlanceSupport"],
            path: "Tests/GlanceSupportTests"
        ),
        .testTarget(
            name: "GlanceMonitorTests",
            dependencies: ["GlanceMonitor"],
            path: "Tests/GlanceMonitorTests"
        ),
        .testTarget(
            name: "GlanceTimeTests",
            dependencies: ["GlanceTime"],
            path: "Tests/GlanceTimeTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
