// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorderDomain",
    products: [
        .library(name: "BlitzRecorderDomain", targets: ["BlitzRecorderDomain"])
    ],
    targets: [
        .target(name: "BlitzRecorderDomain"),
        .testTarget(
            name: "BlitzRecorderDomainTests",
            dependencies: ["BlitzRecorderDomain"]
        )
    ]
)
