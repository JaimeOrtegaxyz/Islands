// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Islands",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Islands",
            path: "Sources",
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
        )
    ]
)
