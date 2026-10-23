// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorderDomain",
    products: [
        .library(name: "BlitzRecorderDomain", targets: ["BlitzRecorderDomain"])
    ],
    targets: [
        // Data races in this module are compile errors waiting to happen, not warnings to ignore.
        .target(name: "BlitzRecorderDomain", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
        .testTarget(
            name: "BlitzRecorderDomainTests",
            dependencies: ["BlitzRecorderDomain"]
        )
    ]
)
