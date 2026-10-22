import XCTest
@testable import BlitzRecorderCore

final class RemoteCameraMessagesTests: XCTestCase {
    private let macIdentity = RemoteCameraMacIdentity(
        publicKeyData: Data([1, 2, 3, 4]),
        publicKeyFingerprint: "fingerprint"
    )
    private let pairingProof = RemoteCameraPairingProof(
        challengeNonce: Data([9, 8, 7, 6]),
        signatureData: Data([5, 4, 3, 2])
    )

    func testCommandRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraCommand.applySettings(RemoteCameraSettings(
            lens: .telephoto,
            formatID: "4k-30",
            frameRate: 60,
            captureProfileID: .proRes422,
            colorMode: .appleLog2,
            zoomFactor: 2.5,
            focusMode: .manual,
            focusPosition: 0.65,
            exposureMode: .manual,
            exposureBias: -0.3,
            iso: 320,
            shutterDurationSeconds: 1.0 / 120.0,
            whiteBalanceMode: .manual,
            whiteBalanceTemperature: 4_800,
            whiteBalanceTint: 12,
            stabilizationMode: .cinematic,
            rotationDegrees: 180,
            torchEnabled: true,
            cinematicVideoEnabled: true,
            cinematicAperture: 2.8
        )))
    }

    func testPairCommandRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraCommand.pair(
            shortCode: "123456",
            macIdentity: macIdentity,
            proof: pairingProof
        ))
    }

    func testHelloCommandRoundTripIncludesMacIdentity() throws {
        try assertCodableRoundTrip(RemoteCameraCommand.hello(protocolVersion: 1, macIdentity: macIdentity, macName: "Studio Mac"))
    }

    func testRequestTransferCommandRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraCommand.requestTransfer(takeID: UUID(), resumeOffset: 1_048_576))
    }

    func testTransferAckCommandRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraCommand.transferAck(takeID: UUID(), receivedByteCount: 524_288))
    }

    func testPairingChallengeEventRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraEvent.pairingChallenge(RemoteCameraPairingChallenge(
            deviceID: UUID(),
            deviceName: "Alice iPhone",
            shortCode: "123456",
            challengeNonce: Data([1, 3, 5, 7]),
            requiresShortCode: true
        )))
    }

    func testTransferChunkEventRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraEvent.transferChunk(
            takeID: UUID(),
            offset: 262_144,
            data: Data([0, 1, 2, 253, 254, 255]),
            isFinal: true
        ))
    }

    func testTransferReadyEventRoundTripIncludesManifest() throws {
        let takeID = UUID()
        let manifest = RemoteCameraTransferManifest(
            takeID: takeID,
            recordingID: takeID,
            fileName: "camera.mov",
            byteCount: 4_194_304,
            durationSeconds: 12,
            settings: RemoteCameraSettings(
                lens: .wide,
                formatID: "1080p-30",
                frameRate: 30,
                captureProfileID: .highEfficiency
            ),
            format: RemoteCameraFormat(
                id: "1080p-30",
                width: 1920,
                height: 1080,
                frameRates: [30],
                supportsStabilization: true,
                supportsHDR: false,
                supportsCinematicVideo: true
            ),
            captureProfileID: .highEfficiency,
            captureCodecLabel: "HEVC",
            captureFormatLabel: "1920x1080 @ 30 fps",
            deviceStartTime: 100,
            deviceStopTime: 200,
            hostStartTime: 90,
            hostStopTime: 210,
            hostTimelineStartTime: 80,
            estimatedHostStartTime: 95,
            recordingDiagnostics: RemoteCameraRecordingDiagnostics(
                captureFormatID: "1080p-30",
                captureFrameRate: 30,
                captureColorMode: .standard,
                captureStabilizationMode: .cinematic,
                captureRotationDegrees: 90,
                cinematicVideoCaptureEnabled: true,
                cinematicFocusMetadataEnabled: true,
                simulatedAperture: 2.8,
                recordsOrientationAndMirroringChangesAsMetadataTrack: true,
                firstOrderAmbisonicsAudioSupported: true,
                firstOrderAmbisonicsAudioEnabled: true,
                captureWarning: "Cinematic needs more light",
                observedAtDeviceStartTime: 100
            )
        )

        let decoded = try assertCodableRoundTrip(RemoteCameraEvent.transferReady(
            takeID: takeID,
            fileName: "camera.mov",
            byteCount: 4_194_304,
            manifest: manifest
        ))

        guard case .transferReady(_, _, _, let manifest) = decoded else {
            return XCTFail("Expected transferReady event")
        }
        let diagnostics = manifest.recordingDiagnostics
        XCTAssertEqual(manifest.format?.supportsCinematicVideo, true)
        XCTAssertEqual(diagnostics?.captureFormatID, "1080p-30")
        XCTAssertEqual(diagnostics?.captureFrameRate, 30)
        XCTAssertEqual(diagnostics?.captureColorMode, .standard)
        XCTAssertEqual(diagnostics?.captureStabilizationMode, .cinematic)
        XCTAssertEqual(diagnostics?.captureRotationDegrees, 90)
        XCTAssertEqual(diagnostics?.cinematicVideoCaptureEnabled, true)
        XCTAssertEqual(diagnostics?.cinematicFocusMetadataEnabled, true)
        XCTAssertEqual(diagnostics?.simulatedAperture, 2.8)
        XCTAssertEqual(diagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack, true)
        XCTAssertEqual(diagnostics?.firstOrderAmbisonicsAudioSupported, true)
        XCTAssertEqual(diagnostics?.firstOrderAmbisonicsAudioEnabled, true)
        XCTAssertEqual(diagnostics?.captureWarning, "Cinematic needs more light")
    }

    func testTransferManifestDecodesLegacyPayloadWithoutRecordingDiagnostics() throws {
        let takeID = UUID()
        let manifest: RemoteCameraTransferManifest = try decodeJSON("""
        {
          "takeID": "\(takeID.uuidString)",
          "recordingID": "\(takeID.uuidString)",
          "fileName": "camera.mov",
          "byteCount": 1024,
          "durationSeconds": 2.5,
          "settings": {
            "lens": "wide",
            "frameRate": 30
          }
        }
        """)

        XCTAssertEqual(manifest.takeID, takeID)
        XCTAssertNil(manifest.recordingDiagnostics)
        XCTAssertEqual(manifest.settings.frameRate, 30)
    }

    func testTransferCompleteEventRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraEvent.transferComplete(
            takeID: UUID(),
            byteCount: 4_194_304,
            sha256: "0123456789abcdef"
        ))
    }

    func testMonitorFrameEventRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraEvent.monitorFrame(
            jpegData: Data([0xff, 0xd8, 0xff, 0xd9]),
            width: 640,
            height: 360
        ))
    }

    func testMonitorVideoFrameEventRoundTrip() throws {
        try assertCodableRoundTrip(RemoteCameraEvent.monitorVideoFrame(RemoteCameraMonitorVideoFrame(
            codec: .h264,
            data: Data([0, 0, 0, 4, 0x65, 0x88, 0x84, 0x21]),
            width: 640,
            height: 360,
            presentationTimeSeconds: 12.25,
            frameDurationSeconds: 1.0 / 24.0,
            isKeyFrame: true,
            sequenceNumber: 42,
            h264SPS: Data([0x67, 0x42]),
            h264PPS: Data([0x68, 0xce])
        )))
    }

    func testMonitorVideoFrameDecodesLegacyPayloadWithoutFrameDuration() throws {
        let decoded: RemoteCameraMonitorVideoFrame = try decodeJSON("""
        {
          "codec": "h264",
          "data": "AAAA",
          "width": 640,
          "height": 360,
          "presentationTimeSeconds": 12.25,
          "isKeyFrame": false,
          "sequenceNumber": 42
        }
        """)

        XCTAssertNil(decoded.frameDurationSeconds)
        XCTAssertEqual(decoded.width, 640)
        XCTAssertEqual(decoded.height, 360)
        XCTAssertEqual(decoded.sequenceNumber, 42)
    }
}
