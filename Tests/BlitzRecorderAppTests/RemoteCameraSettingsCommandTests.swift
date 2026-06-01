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

    private func makeCapabilities(proResAvailable: Bool = true) -> RemoteCameraCapabilities {
        RemoteCameraCapabilities(
            deviceName: "iPhone",
            deviceModelIdentifier: "iPhone18,2",
            supportedLenses: [.wide, .telephoto],
            lensCapabilities: [
                makeLensCapabilities(
                    lens: .wide,
                    formatID: "wide-4k",
                    supportsCinematicVideo: true,
                    proResAvailable: proResAvailable
                ),
                makeLensCapabilities(
                    lens: .telephoto,
                    formatID: "tele-1080",
                    supportsCinematicVideo: false,
                    proResAvailable: true
                )
            ],
            supportedFormats: [makeFormat(id: "wide-4k")],
            supportsTorch: false,
            supportsManualFocus: true,
            supportsFocusLock: true,
            supportsManualExposure: true,
            supportsExposureLock: true,
            supportsWhiteBalanceLock: true,
            supportsManualWhiteBalance: true,
            supportedStabilizationModes: [.off, .auto],
            minimumExposureBias: -2,
            maximumExposureBias: 2
        )
    }

    private func makeLensCapabilities(
        lens: RemoteCameraLens,
        formatID: String,
        supportsCinematicVideo: Bool,
        proResAvailable: Bool
    ) -> RemoteCameraLensCapabilities {
        RemoteCameraLensCapabilities(
            lens: lens,
            supportedFormats: [makeFormat(id: formatID)],
            supportedCaptureProfiles: [
                RemoteCameraCaptureProfile(id: .automatic),
                RemoteCameraCaptureProfile(
                    id: .proRes422,
                    isAvailable: proResAvailable,
                    unavailableReason: proResAvailable ? nil : "ProRes unavailable",
                    supportedFormatIDs: [formatID]
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
            supportedStabilizationModes: [.off, .auto],
            minimumExposureBias: -2,
            maximumExposureBias: 2,
            supportsCinematicVideo: supportsCinematicVideo,
            minimumCinematicAperture: supportsCinematicVideo ? 1.4 : nil,
            maximumCinematicAperture: supportsCinematicVideo ? 16 : nil,
            defaultCinematicAperture: supportsCinematicVideo ? 2.8 : nil
        )
    }

    private func makeFormat(id: String) -> RemoteCameraFormat {
        RemoteCameraFormat(
            id: id,
            width: 1920,
            height: 1080,
            frameRates: [30],
            supportsStabilization: true,
            supportsHDR: true
        )
    }
}
