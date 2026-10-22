import XCTest
@testable import BlitzRecorderCore

final class RemoteCameraSettingsResolverTests: XCTestCase {
    func testRemoteCameraSettingsResolverClampsToCapabilities() {
        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                lens: .telephoto,
                formatID: "4k",
                frameRate: 60,
                captureProfileID: .proRes422,
                zoomFactor: 3,
                focusMode: .manual,
                focusPosition: 2,
                exposureMode: .manual,
                exposureBias: 9,
                iso: 2_000,
                shutterDurationSeconds: 10,
                whiteBalanceMode: .manual,
                whiteBalanceTemperature: 7_000,
                whiteBalanceTint: 4,
                stabilizationMode: .cinematic,
                rotationDegrees: 91,
                torchEnabled: true,
                cinematicVideoEnabled: true,
                cinematicAperture: 20
            ),
            capabilities: makeResolverCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.lens, .wide)
        XCTAssertEqual(resolved.formatID, "1080p")
        XCTAssertEqual(resolved.frameRate, 30)
        XCTAssertEqual(resolved.captureProfileID, .automatic)
        XCTAssertEqual(resolved.colorMode, .standard)
        XCTAssertEqual(resolved.zoomFactor, 1)
        XCTAssertEqual(resolved.torchEnabled, false)
        XCTAssertEqual(resolved.focusPosition, 1)
        XCTAssertEqual(resolved.exposureMode, .continuousAuto)
        XCTAssertEqual(resolved.whiteBalanceMode, .continuousAuto)
        XCTAssertEqual(resolved.stabilizationMode, .off)
        XCTAssertEqual(resolved.rotationDegrees, 0)
        XCTAssertEqual(resolved.cinematicVideoEnabled, false)
        XCTAssertNil(resolved.cinematicAperture)
    }

    func testRemoteCameraSettingsResolverKeepsSupportedRotation() {
        var capabilities = makeResolverCapabilities()
        capabilities.supportedRotationDegrees = [0, 90, 180, 270]

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(rotationDegrees: 90),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.rotationDegrees, 90)
    }

    func testRemoteCameraSettingsResolverFiltersProfileFormatsAndAspectRatio() {
        let formats = [
            RemoteCameraFormat(id: "1080p", width: 1920, height: 1080, frameRates: [30], supportsStabilization: false, supportsHDR: false),
            RemoteCameraFormat(id: "4k", width: 3840, height: 2160, frameRates: [30], supportsStabilization: false, supportsHDR: false)
        ]
        let profiles = [
            RemoteCameraCaptureProfile(id: .automatic),
            RemoteCameraCaptureProfile(id: .highEfficiency, supportedFormatIDs: ["4k"])
        ]

        let filtered = RemoteCameraSettingsResolver.formats(formats, supportedBy: .highEfficiency, profiles: profiles)

        XCTAssertEqual(filtered.map(\.id), ["4k"])
        XCTAssertEqual(
            RemoteCameraSettingsResolver.aspectRatio(width: 1920, height: 1080, rotationDegrees: 180),
            9.0 / 16.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RemoteCameraSettingsResolver.aspectRatio(width: 1920, height: 1080, rotationDegrees: 90),
            16.0 / 9.0,
            accuracy: 0.0001
        )
        XCTAssertTrue(RemoteCameraSettingsResolver.isPortraitRotation(180))
        XCTAssertTrue(RemoteCameraSettingsResolver.isPortraitRotation(0))
        XCTAssertFalse(RemoteCameraSettingsResolver.isPortraitRotation(90))
        XCTAssertFalse(RemoteCameraSettingsResolver.isPortraitRotation(270))
    }

    func testRemoteCameraSettingsResolverFiltersFrameRatesByProfileAndColorMode() {
        let format = RemoteCameraFormat(
            id: "4k",
            width: 3840,
            height: 2160,
            frameRates: [30, 60, 120],
            colorModes: [.standard, .appleLog2],
            colorModeFrameRates: [.standard: [30, 60, 120], .appleLog2: [30, 60]],
            supportsStabilization: false,
            supportsHDR: true
        )
        let profiles = [
            RemoteCameraCaptureProfile(id: .automatic),
            RemoteCameraCaptureProfile(
                id: .proRes422,
                supportedFormatIDs: ["4k"],
                supportedFormatFrameRates: ["4k": [30, 60]]
            )
        ]
        let frameRates = RemoteCameraSettingsResolver.compatibleFrameRates(
            for: format,
            profileID: .proRes422,
            colorMode: .appleLog2,
            profiles: profiles
        )

        XCTAssertEqual(frameRates, [30, 60])

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "4k",
                frameRate: 120,
                captureProfileID: .proRes422,
                colorMode: .appleLog2
            ),
            capabilities: .fixture {
                $0.supportedFormats = [format]
                $0.supportedCaptureProfiles = profiles
            },
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.colorMode, .appleLog2)
        XCTAssertEqual(resolved.captureProfileID, .proRes422)
        XCTAssertEqual(resolved.frameRate, 30)
    }

    func testRemoteCameraSettingsResolverUsesLensSpecificFormats() {
        let capabilities = RemoteCameraCapabilities.fixture {
            $0.supportedLenses = [.wide, .telephoto]
            $0.lensCapabilities = [
                makeLensCapabilities(
                    lens: .telephoto,
                    formats: [
                        RemoteCameraFormat(
                            id: "tele-4k",
                            width: 3840,
                            height: 2160,
                            frameRates: [30, 60],
                            supportsStabilization: true,
                            supportsHDR: true
                        )
                    ]
                )
            ]
            $0.supportedFormats = [
                RemoteCameraFormat(
                    id: "wide-1080p",
                    width: 1920,
                    height: 1080,
                    frameRates: [30],
                    supportsStabilization: false,
                    supportsHDR: false
                )
            ]
        }

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                lens: .telephoto,
                formatID: "tele-4k",
                frameRate: 60,
                stabilizationMode: .standard
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.lens, .telephoto)
        XCTAssertEqual(resolved.formatID, "tele-4k")
        XCTAssertEqual(resolved.frameRate, 60)
        XCTAssertEqual(resolved.stabilizationMode, .standard)
    }

    func testRemoteCameraSettingsResolverSelectsCinematicFormatWhenSupportIsKnown() {
        let capabilities = RemoteCameraCapabilities.fixture {
            $0.supportedFormats = [
                RemoteCameraFormat(
                    id: "4k",
                    width: 3840,
                    height: 2160,
                    frameRates: [30, 60],
                    colorModes: [.standard, .appleLog2],
                    colorModeFrameRates: [.appleLog2: [30, 60]],
                    supportsStabilization: true,
                    supportsHDR: true,
                    supportsCinematicVideo: false
                ),
                cinematicFormat
            ]
            $0.supportedCaptureProfiles = [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(
                    id: .highEfficiency,
                    supportedFormatIDs: ["1080p-cinematic"],
                    supportedFormatFrameRates: ["1080p-cinematic": [30]]
                ),
                RemoteCameraCaptureProfile(
                    id: .proRes422,
                    supportedFormatIDs: ["4k"],
                    supportedFormatFrameRates: ["4k": [30, 60]]
                )
            ]
            $0.enableCinematicVideo()
        }

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "4k",
                frameRate: 60,
                captureProfileID: .proRes422,
                colorMode: .appleLog2,
                cinematicVideoEnabled: true,
                cinematicAperture: 2.8
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.formatID, "1080p-cinematic")
        XCTAssertEqual(resolved.frameRate, 30)
        XCTAssertEqual(resolved.captureProfileID, .highEfficiency)
        XCTAssertEqual(resolved.colorMode, .standard)
        XCTAssertEqual(resolved.cinematicVideoEnabled, true)
        XCTAssertEqual(resolved.cinematicAperture, 2.8)
    }

    func testRemoteCameraSettingsResolverFallsBackToAutomaticCinematicProfileWithoutHEVC() {
        let capabilities = RemoteCameraCapabilities.fixture {
            $0.supportedFormats = [cinematicFormat]
            $0.supportedCaptureProfiles = [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(id: .highEfficiency, isAvailable: false)
            ]
            $0.enableCinematicVideo()
        }

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "1080p-cinematic",
                frameRate: 30,
                captureProfileID: .proRes422,
                cinematicVideoEnabled: true
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.captureProfileID, .automatic)
        XCTAssertTrue(resolved.cinematicVideoEnabled)
        XCTAssertEqual(resolved.colorMode, .standard)
    }

    func testRemoteCameraSettingsResolverKeepsCinematicWhenFormatSupportIsUnknown() {
        let capabilities = RemoteCameraCapabilities.fixture {
            $0.supportedFormats = [
                RemoteCameraFormat(
                    id: "4k",
                    width: 3840,
                    height: 2160,
                    frameRates: [30],
                    supportsStabilization: true,
                    supportsHDR: true
                )
            ]
            $0.enableCinematicVideo()
        }

        let resolved = RemoteCameraSettingsResolver.normalized(
            RemoteCameraSettings(
                formatID: "4k",
                frameRate: 30,
                cinematicVideoEnabled: true,
                cinematicAperture: 4
            ),
            capabilities: capabilities,
            preferredFrameRate: 30
        )

        XCTAssertEqual(resolved.formatID, "4k")
        XCTAssertEqual(resolved.frameRate, 30)
        XCTAssertEqual(resolved.cinematicVideoEnabled, true)
        XCTAssertEqual(resolved.cinematicAperture, 4)
    }

    private let cinematicFormat = RemoteCameraFormat(
        id: "1080p-cinematic",
        width: 1920,
        height: 1080,
        frameRates: [30],
        supportsStabilization: true,
        supportsHDR: false,
        supportsCinematicVideo: true
    )

    private func makeResolverCapabilities() -> RemoteCameraCapabilities {
        .fixture {
            $0.supportedFormats = [
                RemoteCameraFormat(
                    id: "1080p",
                    width: 1920,
                    height: 1080,
                    frameRates: [24, 30],
                    supportsStabilization: false,
                    supportsHDR: false
                )
            ]
            $0.supportedCaptureProfiles = [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(id: .proRes422, isAvailable: false)
            ]
            $0.supportedRotationDegrees = [0, 180]
        }
    }

    private func makeLensCapabilities(
        lens: RemoteCameraLens,
        formats: [RemoteCameraFormat]
    ) -> RemoteCameraLensCapabilities {
        RemoteCameraLensCapabilities(
            lens: lens,
            supportedFormats: formats,
            supportedCaptureProfiles: [RemoteCameraCaptureProfile(id: .automatic)],
            supportsTorch: false,
            minimumZoomFactor: 1,
            maximumZoomFactor: 1,
            supportsManualFocus: false,
            supportsFocusLock: false,
            supportsManualExposure: false,
            supportsExposureLock: false,
            supportsWhiteBalanceLock: false,
            supportsManualWhiteBalance: false,
            supportedStabilizationModes: [.off, .standard],
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )
    }
}
