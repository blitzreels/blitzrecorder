// swift-tools-version: 5.9
import Foundation
import PackageDescription

let directDistribution = ProcessInfo.processInfo.environment["DIRECT_DISTRIBUTION"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(path: "Packages/BlitzRecorderCore"),
    .package(path: "Packages/BlitzRecorderTransport")
]

var appDependencies: [Target.Dependency] = [
    .product(name: "BlitzRecorderCore", package: "BlitzRecorderCore"),
    .product(name: "BlitzRecorderTransport", package: "BlitzRecorderTransport")
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
                .copy("PrivacyInfo.xcprivacy")
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
