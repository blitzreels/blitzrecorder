// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlitzRecorder",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "BlitzRecorder", targets: ["BlitzRecorderApp"])
    ],
    dependencies: [
        .package(path: "Packages/BlitzRecorderCore"),
        .package(path: "Packages/BlitzRecorderTransport")
    ],
    targets: [
        .executableTarget(
            name: "BlitzRecorderApp",
            dependencies: [
                .product(name: "BlitzRecorderCore", package: "BlitzRecorderCore"),
                .product(name: "BlitzRecorderTransport", package: "BlitzRecorderTransport")
            ],
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
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
