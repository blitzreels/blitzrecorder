// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorderDesign",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "BlitzRecorderDesign", targets: ["BlitzRecorderDesign"])
    ],
    targets: [
        .target(name: "BlitzRecorderDesign")
    ]
)
