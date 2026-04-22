// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Islands",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Islands",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
