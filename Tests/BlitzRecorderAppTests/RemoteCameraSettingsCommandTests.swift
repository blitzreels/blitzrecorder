import BlitzRecorderCore
@testable import BlitzRecorderApp
import XCTest

final class RemoteCameraSettingsCommandTests: XCTestCase {
    func testCinematicEnableUsesLensDefaultAperture() {
        let result = RemoteCameraSettingsCommand.apply(
            .cinematicVideoEnabled(true),
            to: RemoteCameraSettings(lens: .wide, frameRate: 30),
            capabilities: makeCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertTrue(result.didChange)
        XCTAssertNil(result.message)
        XCTAssertTrue(result.settings.cinematicVideoEnabled)
        XCTAssertEqual(result.settings.cinematicAperture, 2.8)
        XCTAssertEqual(result.settings.focusMode, .continuousAuto)
        XCTAssertEqual(result.settings.stabilizationMode, .cinematic)
    }

    func testUnavailableCaptureProfileReturnsMessageWithoutChangingSettings() {
        let currentSettings = RemoteCameraSettings(lens: .wide, frameRate: 30, captureProfileID: .automatic)

        let result = RemoteCameraSettingsCommand.apply(
            .captureProfile(.proRes422),
            to: currentSettings,
            capabilities: makeCapabilities(proResAvailable: false),
            preferredFrameRate: 30
        )

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(result.settings, currentSettings)
        XCTAssertEqual(result.message, "ProRes unavailable")
    }

    func testChangingToLensWithoutCinematicClearsCinematicSettings() {
        let currentSettings = RemoteCameraSettings(
            lens: .wide,
            frameRate: 30,
            cinematicVideoEnabled: true,
            cinematicAperture: 2.8
        )

        let result = RemoteCameraSettingsCommand.apply(
            .lens(.telephoto),
            to: currentSettings,
            capabilities: makeCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertEqual(result.settings.lens, .telephoto)
        XCTAssertFalse(result.settings.cinematicVideoEnabled)
        XCTAssertNil(result.settings.cinematicAperture)
        XCTAssertEqual(result.settings.zoomFactor, 1)
        XCTAssertFalse(result.settings.torchEnabled)
    }

    func testAppleLogSelectionSwitchesToProRes() {
        let result = RemoteCameraSettingsCommand.apply(
            .colorMode(.appleLog2),
            to: RemoteCameraSettings(lens: .wide, frameRate: 30),
            capabilities: makeCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.settings.colorMode, .appleLog2)
        XCTAssertEqual(result.settings.captureProfileID, .proRes422)
    }

    func testCinematicClearsAppleLogMode() {
        let currentSettings = RemoteCameraSettings(
            lens: .wide,
            frameRate: 30,
            captureProfileID: .proRes422,
            colorMode: .appleLog2
        )

        let result = RemoteCameraSettingsCommand.apply(
            .cinematicVideoEnabled(true),
            to: currentSettings,
            capabilities: makeCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertEqual(result.settings.colorMode, .standard)
        XCTAssertEqual(result.settings.captureProfileID, .highEfficiency)
        XCTAssertTrue(result.settings.cinematicVideoEnabled)
    }

    func testCinematicEnableSelectsBestThirtyFpsFormat() {
        let result = RemoteCameraSettingsCommand.apply(
            .cinematicVideoEnabled(true),
            to: RemoteCameraSettings(lens: .wide, formatID: "wide-1080", frameRate: 60),
            capabilities: makeCapabilities(wideFormats: [
                makeFormat(id: "wide-1080", width: 1920, height: 1080),
                makeFormat(id: "wide-4k", width: 3840, height: 2160)
            ]),
            preferredFrameRate: 60
        )

        XCTAssertTrue(result.settings.cinematicVideoEnabled)
        XCTAssertEqual(result.settings.formatID, "wide-4k")
        XCTAssertEqual(result.settings.frameRate, 30)
        XCTAssertEqual(result.settings.captureProfileID, .highEfficiency)
        XCTAssertEqual(result.settings.colorMode, .standard)
    }

    func testCinematicEnablePrefersCinematicFormatOverHigherNonCinematicFormat() {
        let result = RemoteCameraSettingsCommand.apply(
            .cinematicVideoEnabled(true),
            to: RemoteCameraSettings(lens: .wide, formatID: "wide-4k", frameRate: 60),
            capabilities: makeCapabilities(wideFormats: [
                makeFormat(id: "wide-4k", width: 3840, height: 2160, supportsCinematicVideo: false),
                makeFormat(id: "wide-1080", width: 1920, height: 1080, supportsCinematicVideo: true)
            ]),
            preferredFrameRate: 60
        )

        XCTAssertTrue(result.settings.cinematicVideoEnabled)
        XCTAssertEqual(result.settings.formatID, "wide-1080")
        XCTAssertEqual(result.settings.frameRate, 30)
    }

    func testCinematicEnableKeepsLegacyFormatFallbackWhenFormatSupportIsUnknown() {
        let result = RemoteCameraSettingsCommand.apply(
            .cinematicVideoEnabled(true),
            to: RemoteCameraSettings(lens: .wide, formatID: "wide-1080", frameRate: 60),
            capabilities: makeCapabilities(wideFormats: [
                makeFormat(id: "wide-1080", width: 1920, height: 1080, supportsCinematicVideo: false),
                makeFormat(id: "wide-4k", width: 3840, height: 2160, supportsCinematicVideo: false)
            ]),
            preferredFrameRate: 60
        )

        XCTAssertTrue(result.settings.cinematicVideoEnabled)
        XCTAssertEqual(result.settings.formatID, "wide-4k")
        XCTAssertEqual(result.settings.frameRate, 30)
    }

    func testCinematicApertureAppliesCinematicDefaults() {
        let currentSettings = RemoteCameraSettings(
            lens: .wide,
            frameRate: 30,
            captureProfileID: .proRes422,
            colorMode: .appleLog2,
            stabilizationMode: .off
        )

        let result = RemoteCameraSettingsCommand.apply(
            .cinematicAperture(1.4),
            to: currentSettings,
            capabilities: makeCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertTrue(result.settings.cinematicVideoEnabled)
        XCTAssertEqual(result.settings.cinematicAperture, 1.4)
        XCTAssertEqual(result.settings.colorMode, .standard)
        XCTAssertEqual(result.settings.captureProfileID, .highEfficiency)
        XCTAssertEqual(result.settings.stabilizationMode, .cinematic)
    }

    func testCinematicEnableFallsBackToAutomaticWhenHEVCProfileUnavailable() {
        let result = RemoteCameraSettingsCommand.apply(
            .cinematicVideoEnabled(true),
            to: RemoteCameraSettings(lens: .wide, frameRate: 30, captureProfileID: .proRes422),
            capabilities: makeCapabilities(hevcAvailable: false),
            preferredFrameRate: 30
        )

        XCTAssertTrue(result.settings.cinematicVideoEnabled)
        XCTAssertEqual(result.settings.captureProfileID, .automatic)
        XCTAssertEqual(result.settings.colorMode, .standard)
    }

    func testCinematicEnableFallsBackToAutoStabilizationWhenCinematicModeUnavailable() {
        let result = RemoteCameraSettingsCommand.apply(
            .cinematicVideoEnabled(true),
            to: RemoteCameraSettings(lens: .wide, frameRate: 30, stabilizationMode: .off),
            capabilities: makeCapabilities(supportedStabilizationModes: [.off, .auto]),
            preferredFrameRate: 30
        )

        XCTAssertTrue(result.settings.cinematicVideoEnabled)
        XCTAssertEqual(result.settings.stabilizationMode, .auto)
    }

    func testRotationOverrideDisablesAutomaticRotation() {
        let result = RemoteCameraSettingsCommand.apply(
            .rotationDegrees(90),
            to: RemoteCameraSettings(usesAutomaticRotation: true, rotationDegrees: 180),
            capabilities: makeCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertTrue(result.didChange)
        XCTAssertFalse(result.settings.usesAutomaticRotation)
        XCTAssertEqual(result.settings.rotationDegrees, 90)
    }

    func testAutomaticRotationCanBeReenabled() {
        let result = RemoteCameraSettingsCommand.apply(
            .automaticRotation(true),
            to: RemoteCameraSettings(usesAutomaticRotation: false, rotationDegrees: 90),
            capabilities: makeCapabilities(),
            preferredFrameRate: 30
        )

        XCTAssertTrue(result.didChange)
        XCTAssertTrue(result.settings.usesAutomaticRotation)
        XCTAssertEqual(result.settings.rotationDegrees, 90)
    }

    private func makeCapabilities(
        proResAvailable: Bool = true,
        hevcAvailable: Bool = true,
        supportedStabilizationModes: [RemoteCameraStabilizationMode] = [.off, .cinematic, .auto],
        wideFormats: [RemoteCameraFormat]? = nil
    ) -> RemoteCameraCapabilities {
        let wideFormats = wideFormats ?? [makeFormat(id: "wide-4k")]
        return RemoteCameraCapabilities(
            deviceName: "iPhone",
            deviceModelIdentifier: "iPhone18,2",
            supportedLenses: [.wide, .telephoto],
            lensCapabilities: [
                makeLensCapabilities(
                    lens: .wide,
                    formats: wideFormats,
                    supportsCinematicVideo: true,
                    hevcAvailable: hevcAvailable,
                    proResAvailable: proResAvailable,
                    supportedStabilizationModes: supportedStabilizationModes
                ),
                makeLensCapabilities(
                    lens: .telephoto,
                    formats: [makeFormat(id: "tele-1080")],
                    supportsCinematicVideo: false,
                    hevcAvailable: hevcAvailable,
                    proResAvailable: true,
                    supportedStabilizationModes: supportedStabilizationModes
                )
            ],
            supportedFormats: wideFormats,
            supportsTorch: false,
            supportsManualFocus: true,
            supportsFocusLock: true,
            supportsManualExposure: true,
            supportsExposureLock: true,
            supportsWhiteBalanceLock: true,
            supportsManualWhiteBalance: true,
            supportedStabilizationModes: supportedStabilizationModes,
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )
    }

    private func makeLensCapabilities(
        lens: RemoteCameraLens,
        formats: [RemoteCameraFormat],
        supportsCinematicVideo: Bool,
        hevcAvailable: Bool,
        proResAvailable: Bool,
        supportedStabilizationModes: [RemoteCameraStabilizationMode]
    ) -> RemoteCameraLensCapabilities {
        RemoteCameraLensCapabilities(
            lens: lens,
            supportedFormats: formats,
            supportedCaptureProfiles: [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(
                    id: .highEfficiency,
                    isAvailable: hevcAvailable,
                    supportedFormatIDs: formats.map(\.id),
                    supportedFormatFrameRates: Dictionary(
                        uniqueKeysWithValues: formats.map { ($0.id, $0.frameRates) }
                    )
                ),
                RemoteCameraCaptureProfile(
                    id: .proRes422,
                    isAvailable: proResAvailable,
                    unavailableReason: proResAvailable ? nil : "ProRes unavailable",
                    supportedFormatIDs: formats.map(\.id),
                    supportedFormatFrameRates: Dictionary(
                        uniqueKeysWithValues: formats.map { ($0.id, $0.frameRates) }
                    )
                )
            ],
            supportsTorch: false,
            minimumZoomFactor: 1,
            maximumZoomFactor: 3,
            supportsManualFocus: true,
            supportsFocusLock: true,
            supportsManualExposure: true,
            supportsExposureLock: true,
            supportsWhiteBalanceLock: true,
            supportsManualWhiteBalance: true,
            supportedStabilizationModes: supportedStabilizationModes,
            minimumExposureBias: -2,
            maximumExposureBias: 2,
            supportsCinematicVideo: supportsCinematicVideo,
            minimumCinematicAperture: supportsCinematicVideo ? 1.4 : nil,
            maximumCinematicAperture: supportsCinematicVideo ? 16 : nil,
            defaultCinematicAperture: supportsCinematicVideo ? 2.8 : nil
        )
    }

    private func makeFormat(
        id: String,
        width: Int = 1920,
        height: Int = 1080,
        supportsCinematicVideo: Bool = false
    ) -> RemoteCameraFormat {
        RemoteCameraFormat(
            id: id,
            width: width,
            height: height,
            frameRates: [30, 60, 120],
            colorModes: [.standard, .appleLog, .appleLog2],
            colorModeFrameRates: [.standard: [30, 60, 120], .appleLog: [30, 60], .appleLog2: [30]],
            supportsStabilization: true,
            supportsHDR: true,
            supportsCinematicVideo: supportsCinematicVideo
        )
    }
}
