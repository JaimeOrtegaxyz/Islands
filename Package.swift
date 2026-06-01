// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Islands",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure, side-effect-free layout logic — no AppKit/Accessibility — so it can
        // be unit-tested without a running app. The executable depends on it.
        .target(
            name: "IslandsCore",
            path: "Sources/IslandsCore"
        ),
        .executableTarget(
            name: "Islands",
            dependencies: [
                "IslandsCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: ["IslandsCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "IslandsCoreTests",
            dependencies: ["IslandsCore"],
            path: "Tests/IslandsCoreTests"
        ),
    ]
)
