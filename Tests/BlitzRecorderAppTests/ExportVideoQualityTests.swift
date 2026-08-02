import AVFoundation
@testable import BlitzRecorderApp
import VideoToolbox
import XCTest

final class ExportVideoQualityTests: XCTestCase {
    func testStandardQualityReducesAutomaticBitrate() {
        XCTAssertEqual(ExportVideoQuality.standard.videoBitrate(baseBitrate: 8_000_000), 5_760_000)
    }

    func testHighQualityPreservesAutomaticBitrate() {
        XCTAssertEqual(ExportVideoQuality.high.videoBitrate(baseBitrate: 8_000_000), 8_000_000)
    }

    func testMaximumQualityRaisesAutomaticBitrate() {
        XCTAssertEqual(ExportVideoQuality.maximum.videoBitrate(baseBitrate: 8_000_000), 12_000_000)
    }

    func testQualityBitrateStaysWithinEncoderLimits() {
        XCTAssertEqual(
            ExportVideoQuality.standard.videoBitrate(baseBitrate: 1_000_000),
            RecordingSettings.minCustomVideoBitrate
        )
        XCTAssertEqual(
            ExportVideoQuality.maximum.videoBitrate(baseBitrate: 100_000_000),
            RecordingSettings.maxCustomVideoBitrate
        )
    }

    func testOptimizedHEVCSettingsFavorOfflineCompressionAndStableSDRColor() throws {
        let settings = OptimizedCompositionExporter.videoOutputSettings(
            for: OptimizedVideoSettingsRequest(
                width: 1_920,
                height: 1_080,
                bitrate: 8_000_000,
                framesPerSecond: 30,
                hardwareEncoderAvailable: true
            )
        )

        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .hevc)
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int, 8_000_000)
        XCTAssertEqual(compression[AVVideoAllowFrameReorderingKey] as? Bool, true)
        XCTAssertEqual(compression[kVTCompressionPropertyKey_RealTime as String] as? Bool, false)

        let color = try XCTUnwrap(settings[AVVideoColorPropertiesKey] as? [String: Any])
        XCTAssertEqual(color[AVVideoColorPrimariesKey] as? String, AVVideoColorPrimaries_ITU_R_709_2)
        XCTAssertEqual(color[AVVideoTransferFunctionKey] as? String, AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(color[AVVideoYCbCrMatrixKey] as? String, AVVideoYCbCrMatrix_ITU_R_709_2)

        let encoder = try XCTUnwrap(settings[AVVideoEncoderSpecificationKey] as? [String: Any])
        XCTAssertEqual(
            encoder[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] as? Bool,
            true
        )
    }
}
