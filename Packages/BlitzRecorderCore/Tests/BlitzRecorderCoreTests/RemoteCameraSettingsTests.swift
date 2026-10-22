import XCTest
@testable import BlitzRecorderCore

final class RemoteCameraSettingsTests: XCTestCase {
    func testRemoteCameraSettingsDecodesLegacyPayloadWithAutomaticProfile() throws {
        let decoded: RemoteCameraSettings = try decodeJSON("""
        {
          "lens": "wide",
          "formatID": "1920x1080",
          "frameRate": 30,
          "zoomFactor": 1.2,
          "focusMode": "continuousAuto",
          "focusPosition": 0.5,
          "exposureMode": "continuousAuto",
          "exposureBias": 0,
          "whiteBalanceMode": "continuousAuto",
          "whiteBalanceTemperature": 5500,
          "whiteBalanceTint": 0,
          "stabilizationMode": "auto",
          "torchEnabled": false
        }
        """)

        XCTAssertEqual(decoded.captureProfileID, .automatic)
        XCTAssertEqual(decoded.colorMode, .standard)
        XCTAssertEqual(decoded.formatID, "1920x1080")
        XCTAssertEqual(decoded.rotationDegrees, RemoteCameraSettings.defaultRotationDegrees)
        XCTAssertEqual(decoded.cinematicVideoEnabled, false)
        XCTAssertNil(decoded.cinematicAperture)
    }

    func testRemoteCameraSettingsNormalizesRotationDegrees() {
        XCTAssertEqual(RemoteCameraSettings().rotationDegrees, 180)
        XCTAssertEqual(RemoteCameraSettings(rotationDegrees: 91).rotationDegrees, 90)
        XCTAssertEqual(RemoteCameraSettings(rotationDegrees: -90).rotationDegrees, 270)
        XCTAssertEqual(RemoteCameraSettings(rotationDegrees: 360).rotationDegrees, 0)
    }

    func testRemoteCameraCapabilitiesDecodesLegacyPayloadWithAutomaticProfile() throws {
        let decoded: RemoteCameraCapabilities = try decodeJSON("""
        {
          "deviceName": "Alice iPhone",
          "supportedLenses": ["wide"],
          "supportedFormats": [],
          "supportsTorch": false,
          "supportsManualFocus": false,
          "supportsFocusLock": false,
          "supportsManualExposure": false,
          "supportsExposureLock": false,
          "supportsWhiteBalanceLock": false,
          "supportsManualWhiteBalance": false,
          "supportedStabilizationModes": ["off"],
          "minimumExposureBias": -2,
          "maximumExposureBias": 2
        }
        """)

        XCTAssertEqual(decoded.supportedCaptureProfiles, [RemoteCameraCaptureProfile(id: .automatic)])
        XCTAssertNil(decoded.deviceModelIdentifier)
        XCTAssertEqual(decoded.supportsCinematicVideo, false)
        XCTAssertNil(decoded.minimumCinematicAperture)
    }

    func testRemoteCameraCapabilitiesRoundTripIncludesDeviceModelIdentifier() throws {
        let capabilities = RemoteCameraCapabilities.fixture {
            $0.deviceModelIdentifier = "iPhone15,3"
            $0.supportsTorch = true
            $0.enableCinematicVideo()
        }

        let decoded = try assertCodableRoundTrip(capabilities)

        XCTAssertEqual(decoded.deviceModelIdentifier, "iPhone15,3")
        XCTAssertEqual(decoded.supportsCinematicVideo, true)
        XCTAssertEqual(decoded.defaultCinematicAperture, 2.8)
    }
}
