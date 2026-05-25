// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorderTransport",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "BlitzRecorderTransport", targets: ["BlitzRecorderTransport"])
    ],
    dependencies: [],
    targets: [
        .target(name: "BlitzRecorderTransport"),
        .testTarget(
            name: "BlitzRecorderTransportTests",
            dependencies: ["BlitzRecorderTransport"]
        )
    ]
)
