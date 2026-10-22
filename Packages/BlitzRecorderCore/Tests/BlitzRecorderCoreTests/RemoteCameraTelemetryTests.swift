import XCTest
@testable import BlitzRecorderCore

final class RemoteCameraTelemetryTests: XCTestCase {
    func testTelemetryRoundTripIncludesTransferProgress() throws {
        let telemetry = RemoteCameraTelemetry(
            phase: .transferring,
            elapsedSeconds: 3,
            batteryLevel: 0.8,
            thermalState: "Nominal",
            storageFreeBytes: 1_000_000,
            activeSettings: RemoteCameraSettings(),
            transferProgress: RemoteCameraTransferProgress(
                takeID: UUID(),
                transferredByteCount: 50,
                expectedByteCount: 100
            ),
            previewHealth: RemoteCameraPreviewHealth(
                framesSent: 25,
                framesDropped: 1,
                lastFrameAgeSeconds: 0.2,
                isTransferActive: true
            ),
            captureWarning: "Cinematic needs more light"
        )

        let decoded = try assertCodableRoundTrip(telemetry)

        XCTAssertEqual(decoded.transferProgress?.fraction, 0.5)
        XCTAssertEqual(decoded.previewHealth?.droppedFrameRatio ?? -1, 1.0 / 26.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.previewHealth?.isTransferActive, true)
        XCTAssertEqual(decoded.previewHealth?.isHealthy, false)
        XCTAssertEqual(decoded.captureWarning, "Cinematic needs more light")
    }

    func testTelemetryDecodesWithoutCaptureWarning() throws {
        let decoded: RemoteCameraTelemetry = try decodeJSON("""
        {
          "phase": "idle",
          "elapsedSeconds": 0,
          "batteryLevel": null,
          "thermalState": "Nominal",
          "storageFreeBytes": null,
          "activeSettings": {}
        }
        """)

        XCTAssertNil(decoded.captureWarning)
        XCTAssertEqual(decoded.activeSettings.frameRate, 30)
    }

    func testPreviewHealthFlagsHighDroppedFrameRatio() {
        let waiting = RemoteCameraPreviewHealth(framesSent: 0, framesDropped: 0, lastFrameAgeSeconds: nil)
        let healthy = RemoteCameraPreviewHealth(framesSent: 76, framesDropped: 24, lastFrameAgeSeconds: 0.2)
        let degraded = RemoteCameraPreviewHealth(framesSent: 75, framesDropped: 25, lastFrameAgeSeconds: 0.2)
        let stale = RemoteCameraPreviewHealth(framesSent: 25, framesDropped: 0, lastFrameAgeSeconds: 2)
        let blockedBeforeFirstFrame = RemoteCameraPreviewHealth(
            framesSent: 0,
            framesDropped: 4,
            lastFrameAgeSeconds: nil
        )

        XCTAssertFalse(waiting.isDroppingFrames)
        XCTAssertFalse(waiting.isStale)
        XCTAssertFalse(waiting.isHealthy)
        XCTAssertTrue(waiting.isWaitingForFirstFrame)
        XCTAssertFalse(healthy.isDroppingFrames)
        XCTAssertFalse(healthy.isStale)
        XCTAssertTrue(healthy.isHealthy)
        XCTAssertFalse(healthy.isWaitingForFirstFrame)
        XCTAssertTrue(degraded.isDroppingFrames)
        XCTAssertFalse(degraded.isStale)
        XCTAssertFalse(degraded.isHealthy)
        XCTAssertFalse(degraded.isWaitingForFirstFrame)
        XCTAssertTrue(stale.isStale)
        XCTAssertFalse(stale.isHealthy)
        XCTAssertFalse(stale.isWaitingForFirstFrame)
        XCTAssertTrue(blockedBeforeFirstFrame.isDroppingFrames)
        XCTAssertTrue(blockedBeforeFirstFrame.isBlockedBeforeFirstFrame)
        XCTAssertFalse(blockedBeforeFirstFrame.isWaitingForFirstFrame)
        XCTAssertFalse(blockedBeforeFirstFrame.isHealthy)
    }

    func testPreviewHealthDecodesLegacyPayloadWithoutTransferState() throws {
        let decoded: RemoteCameraPreviewHealth = try decodeJSON("""
        {
          "framesSent": 25,
          "framesDropped": 1,
          "lastFrameAgeSeconds": 0.2
        }
        """)

        XCTAssertFalse(decoded.isTransferActive)
        XCTAssertTrue(decoded.isHealthy)
    }

    func testRecordingWarningAccumulatorKeepsUniqueWarningsSeenDuringTake() {
        var accumulator = RemoteCameraRecordingWarningAccumulator()

        accumulator.record(nil)
        accumulator.record("  ")
        accumulator.record("Cinematic needs more light")
        accumulator.record("Cinematic needs more light")
        accumulator.record(" iPhone camera paused due to system pressure ")

        XCTAssertEqual(
            accumulator.captureWarning,
            "Cinematic needs more light. iPhone camera paused due to system pressure"
        )
    }

    func testRecordingWarningAccumulatorIncludesFinalWarning() {
        var accumulator = RemoteCameraRecordingWarningAccumulator(warnings: [
            "Cinematic needs more light"
        ])

        let warning = accumulator.recordingWarning(including: "Camera interrupted")

        XCTAssertEqual(warning, "Cinematic needs more light. Camera interrupted")
        XCTAssertEqual(accumulator.captureWarning, warning)
    }

    func testRecordingWarningAccumulatorMergesExistingWarningWithoutDroppingHistory() {
        XCTAssertEqual(
            RemoteCameraRecordingWarningAccumulator.mergedWarning(
                "Cinematic needs more light. Camera interrupted",
                "Camera interrupted"
            ),
            "Cinematic needs more light. Camera interrupted"
        )
        XCTAssertEqual(
            RemoteCameraRecordingWarningAccumulator.mergedWarning(
                "Cinematic needs more light",
                "Cinematic focus metadata unavailable"
            ),
            "Cinematic needs more light. Cinematic focus metadata unavailable"
        )
    }

    func testRecordingDiagnosticsMergePreservesCinematicFocusMetadataAndWarnings() {
        let base = RemoteCameraRecordingDiagnostics(
            captureFormatID: "1920x1080",
            cinematicVideoCaptureEnabled: true,
            cinematicFocusMetadataEnabled: true,
            captureWarning: "Cinematic needs more light"
        )
        let update = RemoteCameraRecordingDiagnostics(
            captureFrameRate: 30,
            cinematicFocusMetadataEnabled: false,
            simulatedAperture: 2.8,
            recordedVideoCodecTypes: ["HEVC"],
            recordedMetadataTrackCount: 2,
            cinematicAssetVerified: true,
            cinematicTrackCount: 3,
            cinematicDurationSeconds: 1.2,
            captureWarning: "Cinematic focus metadata unavailable",
            observedAtDeviceStartTime: 42
        )

        let merged = base.merging(update)

        XCTAssertEqual(merged.captureFormatID, "1920x1080")
        XCTAssertEqual(merged.captureFrameRate, 30)
        XCTAssertEqual(merged.cinematicVideoCaptureEnabled, true)
        XCTAssertEqual(merged.cinematicFocusMetadataEnabled, false)
        XCTAssertEqual(merged.simulatedAperture, 2.8)
        XCTAssertEqual(merged.recordedVideoCodecTypes, ["HEVC"])
        XCTAssertEqual(merged.recordedMetadataTrackCount, 2)
        XCTAssertEqual(merged.cinematicAssetVerified, true)
        XCTAssertEqual(merged.cinematicTrackCount, 3)
        XCTAssertEqual(merged.cinematicDurationSeconds, 1.2)
        XCTAssertEqual(
            merged.captureWarning,
            "Cinematic needs more light. Cinematic focus metadata unavailable"
        )
        XCTAssertEqual(merged.observedAtDeviceStartTime, 42)
    }
}
