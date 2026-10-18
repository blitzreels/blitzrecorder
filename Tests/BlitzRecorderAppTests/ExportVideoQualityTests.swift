import AVFoundation
@testable import BlitzRecorderApp
import VideoToolbox
import XCTest

final class ExportVideoQualityTests: XCTestCase {
    func testWebQualityIsH264AtAFixedFiveMegabitAverage() {
        let profile = ExportVideoQuality.web.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(profile.codec, .h264)
        XCTAssertEqual(profile.bitrate, 5_000_000)
        XCTAssertEqual(profile.audioBitrate, 160_000)
        XCTAssertNil(profile.quality)
        XCTAssertTrue(profile.usesAverageBitRate)
        XCTAssertEqual(profile.maxKeyFrameInterval, 60)
        XCTAssertEqual(profile.detail, "H.264 · 5.0 Mbps")
    }

    func testSmallQualityIsHEVCAtAFixedAverage() {
        let profile = ExportVideoQuality.compact.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(profile.codec, .hevc)
        XCTAssertEqual(profile.bitrate, 2_500_000)
        XCTAssertEqual(profile.audioBitrate, 96_000)
        XCTAssertNil(profile.quality)
        XCTAssertTrue(profile.usesAverageBitRate)
        XCTAssertEqual(profile.maxKeyFrameInterval, 150)
    }

    func testHighStandardAndLosslessShareOneFixedHEVCTier() {
        let high = ExportVideoQuality.high.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(high.codec, .hevc)
        XCTAssertEqual(high.bitrate, 10_000_000)
        XCTAssertNil(high.quality)
        XCTAssertTrue(high.usesAverageBitRate)
        XCTAssertTrue(high.prefersFullRangeRGB)
        for legacy in [ExportVideoQuality.standard, .maximum] {
            XCTAssertEqual(legacy.encodingProfile(baseBitrate: 8_000_000, framesPerSecond: 30, audioBitrate: 192_000), high)
            XCTAssertEqual(legacy.resolvedMenuQuality, .high)
        }
        XCTAssertEqual(ExportVideoQuality.menuCases, [.compact, .web, .high, .proRes])
    }

    func testProResIsAlmostLosslessMezzanineInQuickTime() {
        let profile = ExportVideoQuality.proRes.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000,
            width: 1_920,
            height: 1_080
        )

        XCTAssertEqual(profile.codec, .proRes422)
        XCTAssertEqual(profile.bitrate, 147_000_000)
        XCTAssertNil(profile.quality)
        XCTAssertEqual(profile.preferredFormat, .mov)
        XCTAssertEqual(profile.audioBitrate, 320_000)
        XCTAssertTrue(ExportVideoQuality.proRes.requiresQuickTime)
        XCTAssertEqual(ExportVideoQuality.proRes.resolvedOutputFormat(.mp4), .mov)
    }

    func testQualityBitrateStaysWithinEncoderLimits() {
        XCTAssertEqual(
            ExportVideoQuality.compact.videoBitrate(baseBitrate: 1_000_000),
            RecordingSettings.minExportVideoBitrate
        )
        XCTAssertEqual(
            ExportVideoQuality.web.videoBitrate(baseBitrate: 1_000_000),
            625_000
        )
        XCTAssertEqual(
            ExportVideoQuality.standard.videoBitrate(baseBitrate: 1_000_000),
            1_250_000
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
        XCTAssertNil(compression[kVTCompressionPropertyKey_Quality as String])

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

    func testWebExportSettingsUseFixedAverageH264AndTwoSecondKeyframes() throws {
        let encoding = ExportVideoQuality.web.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )
        let settings = OptimizedCompositionExporter.videoOutputSettings(
            for: OptimizedVideoSettingsRequest(
                width: 1_920,
                height: 1_080,
                framesPerSecond: 30,
                hardwareEncoderAvailable: true,
                encoding: encoding
            )
        )

        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .h264)
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int, 5_000_000)
        XCTAssertEqual(compression[AVVideoProfileLevelKey] as? String, AVVideoProfileLevelH264HighAutoLevel)
        XCTAssertEqual(compression[AVVideoMaxKeyFrameIntervalKey] as? Int, 60)
        XCTAssertNil(compression[kVTCompressionPropertyKey_Quality as String])
        let limits = try XCTUnwrap(compression[kVTCompressionPropertyKey_DataRateLimits as String] as? [Int])
        XCTAssertEqual(limits, [625_000, 1])
    }

    func testHighExportHoldsAFixedAverageSoItsSizeIsPredictable() throws {
        let encoding = ExportVideoQuality.maximum.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )
        let settings = OptimizedCompositionExporter.videoOutputSettings(
            for: OptimizedVideoSettingsRequest(
                width: 1_920,
                height: 1_080,
                framesPerSecond: 30,
                hardwareEncoderAvailable: true,
                encoding: encoding
            )
        )

        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .hevc)
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int, 10_000_000)
        XCTAssertNil(compression[kVTCompressionPropertyKey_Quality as String])
        let limits = try XCTUnwrap(compression[kVTCompressionPropertyKey_DataRateLimits as String] as? [Int])
        XCTAssertEqual(limits, [1_250_000, 1])
    }

    func testProResExportUsesMezzanineCodecWithoutBitrateControls() throws {
        let encoding = ExportVideoQuality.proRes.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )
        let settings = OptimizedCompositionExporter.videoOutputSettings(
            for: OptimizedVideoSettingsRequest(
                width: 1_920,
                height: 1_080,
                framesPerSecond: 30,
                hardwareEncoderAvailable: true,
                encoding: encoding
            )
        )

        XCTAssertEqual(settings[AVVideoCodecKey] as? AVVideoCodecType, .proRes422)
        let compression = try XCTUnwrap(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        XCTAssertNil(compression[AVVideoAverageBitRateKey])
        XCTAssertNil(compression[kVTCompressionPropertyKey_Quality as String])
        XCTAssertNil(compression[AVVideoProfileLevelKey])
        XCTAssertEqual(compression[kVTCompressionPropertyKey_RealTime as String] as? Bool, false)
    }

    func testSizeEstimateIsOneNumberFromBitrateAndDuration() {
        let encoding = ExportVideoQuality.web.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )
        XCTAssertEqual(encoding.estimatedBytes(duration: 100, layoutCount: 1), 64_500_000)
        XCTAssertEqual(encoding.estimatedBytes(duration: 100, layoutCount: 2), 129_000_000)
        XCTAssertFalse(encoding.estimatedSizeText(duration: 150, layoutCount: 1).contains("–"))
    }
}
