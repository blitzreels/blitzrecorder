// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorderCore",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "BlitzRecorderCore", targets: ["BlitzRecorderCore"])
    ],
    targets: [
        // Data races in this module are compile errors waiting to happen, not warnings to ignore.
        .target(name: "BlitzRecorderCore", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .testTarget(
            name: "BlitzRecorderCoreTests",
            dependencies: ["BlitzRecorderCore"]
        )
    ]
)
