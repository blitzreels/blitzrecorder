// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorderCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "BlitzRecorderCore", targets: ["BlitzRecorderCore"])
    ],
    targets: [
        .target(name: "BlitzRecorderCore"),
        .testTarget(
            name: "BlitzRecorderCoreTests",
            dependencies: ["BlitzRecorderCore"]
        )
    ]
)
