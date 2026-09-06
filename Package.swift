// swift-tools-version: 5.9
import Foundation
import PackageDescription

let directDistribution = ProcessInfo.processInfo.environment["DIRECT_DISTRIBUTION"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(path: "Packages/BlitzRecorderCore"),
    .package(path: "Packages/BlitzRecorderTransport"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    .package(
        url: "https://github.com/FluidInference/FluidAudio.git",
        exact: "0.15.5"
    )
]

var appDependencies: [Target.Dependency] = [
    .product(name: "BlitzRecorderCore", package: "BlitzRecorderCore"),
    .product(name: "BlitzRecorderTransport", package: "BlitzRecorderTransport"),
    .product(name: "MCP", package: "swift-sdk"),
    .product(name: "NIOCore", package: "swift-nio"),
    .product(name: "NIOHTTP1", package: "swift-nio"),
    .product(name: "NIOPosix", package: "swift-nio"),
    .product(name: "FluidAudio", package: "FluidAudio")
]

var appSwiftSettings: [SwiftSetting] = []

if directDistribution {
    packageDependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"))
    appDependencies.append(.product(name: "Sparkle", package: "Sparkle"))
    appSwiftSettings.append(.define("DIRECT_DISTRIBUTION"))
}

let package = Package(
    name: "BlitzRecorder",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "BlitzRecorder", targets: ["BlitzRecorderApp"])
    ],
    dependencies: packageDependencies,
    targets: [
        .executableTarget(
            name: "BlitzRecorderApp",
            dependencies: appDependencies,
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
                .copy("ThirdPartyNotices.md"),
                .copy("Resources/WebMCPWorkspace.html")
            ],
            swiftSettings: appSwiftSettings,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Cinematic"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Metal"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("Security"),
                .linkedFramework("StoreKit"),
                .linkedFramework("Vision"),
                .linkedFramework("VideoToolbox")
            ]
        ),
        .testTarget(
            name: "BlitzRecorderAppTests",
            dependencies: ["BlitzRecorderApp"]
        )
    ]
)
