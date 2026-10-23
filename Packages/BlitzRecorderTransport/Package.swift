// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorderTransport",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "BlitzRecorderTransport", targets: ["BlitzRecorderTransport"])
    ],
    dependencies: [],
    targets: [
        // Data races in this module are compile errors waiting to happen, not warnings to ignore.
        .target(name: "BlitzRecorderTransport", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .testTarget(
            name: "BlitzRecorderTransportTests",
            dependencies: ["BlitzRecorderTransport"]
        )
    ]
)
