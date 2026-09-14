import AVFoundation
@testable import BlitzRecorderApp
import VideoToolbox
import XCTest

final class ExportVideoQualityTests: XCTestCase {
    func testWebQualityUsesH264AtAFractionOfAutomaticBitrate() {
        let profile = ExportVideoQuality.web.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(profile.codec, .h264)
        XCTAssertEqual(profile.bitrate, 1_600_000)
        XCTAssertEqual(profile.audioBitrate, 128_000)
        XCTAssertEqual(profile.quality ?? -1, 0.40, accuracy: 0.001)
        XCTAssertTrue(profile.usesAverageBitRate)
        XCTAssertEqual(profile.maxKeyFrameInterval, 150)
        XCTAssertEqual(profile.detail, "H.264 · 1.6 Mbps")
    }

    func testCompactQualityUsesHEVCBelowTheOldTwoMegabitFloor() {
        let profile = ExportVideoQuality.compact.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(profile.codec, .hevc)
        XCTAssertEqual(profile.bitrate, 960_000)
        XCTAssertEqual(profile.audioBitrate, 96_000)
        XCTAssertEqual(profile.quality ?? -1, 0.28, accuracy: 0.001)
        XCTAssertTrue(profile.usesAverageBitRate)
        XCTAssertEqual(profile.maxKeyFrameInterval, 150)
        XCTAssertLessThan(profile.bitrate, RecordingSettings.minCustomVideoBitrate)
    }

    func testStandardQualityUsesConstrainedHEVCQuality() {
        let profile = ExportVideoQuality.standard.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(profile.codec, .hevc)
        XCTAssertEqual(profile.bitrate, 6_400_000)
        XCTAssertEqual(profile.quality ?? -1, 0.55, accuracy: 0.001)
        XCTAssertFalse(profile.usesAverageBitRate)
        XCTAssertTrue(profile.sizeEstimateIsCeiling)
    }

    func testHighQualityUsesLightLossCRFWithHeadroom() {
        let profile = ExportVideoQuality.high.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(profile.codec, .hevc)
        XCTAssertEqual(profile.bitrate, 12_000_000)
        XCTAssertEqual(profile.quality ?? -1, 0.72, accuracy: 0.001)
        XCTAssertFalse(profile.usesAverageBitRate)
        XCTAssertTrue(profile.prefersFullRangeRGB)
    }

    func testLosslessQualityUsesNearLosslessHEVCWithoutAverageBitrate() {
        let profile = ExportVideoQuality.maximum.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )

        XCTAssertEqual(profile.codec, .hevc)
        XCTAssertEqual(profile.bitrate, 32_000_000)
        XCTAssertEqual(profile.quality ?? -1, 0.92, accuracy: 0.001)
        XCTAssertFalse(profile.usesAverageBitRate)
        XCTAssertEqual(profile.audioBitrate, 256_000)
        XCTAssertTrue(profile.prefersFullRangeRGB)
        XCTAssertTrue(profile.detail.contains("visually lossless"))
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
            400_000
        )
        XCTAssertEqual(
            ExportVideoQuality.standard.videoBitrate(baseBitrate: 1_000_000),
            800_000
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

    func testWebExportSettingsUseH264QualityCapsAndLongGOP() throws {
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
        XCTAssertEqual(compression[AVVideoAverageBitRateKey] as? Int, 1_600_000)
        XCTAssertEqual(compression[AVVideoProfileLevelKey] as? String, AVVideoProfileLevelH264HighAutoLevel)
        XCTAssertEqual(compression[AVVideoMaxKeyFrameIntervalKey] as? Int, 150)
        XCTAssertEqual((compression[kVTCompressionPropertyKey_Quality as String] as? NSNumber)?.floatValue ?? -1, 0.40, accuracy: 0.001)
        let limits = try XCTUnwrap(compression[kVTCompressionPropertyKey_DataRateLimits as String] as? [Int])
        XCTAssertEqual(limits, [200_000, 1])
    }

    func testLosslessExportOmitsAverageBitRateSoQualityCanBreathe() throws {
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
        XCTAssertNil(compression[AVVideoAverageBitRateKey])
        XCTAssertEqual((compression[kVTCompressionPropertyKey_Quality as String] as? NSNumber)?.floatValue ?? -1, 0.92, accuracy: 0.001)
        let limits = try XCTUnwrap(compression[kVTCompressionPropertyKey_DataRateLimits as String] as? [Int])
        XCTAssertEqual(limits, [4_000_000, 1])
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

    func testLosslessSizeEstimateUsesATypicalRangeNotTheCeiling() {
        let encoding = ExportVideoQuality.maximum.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )
        XCTAssertEqual(encoding.estimatedSizeCaption, "Typical–max")
        XCTAssertEqual(encoding.typicalSizeFraction, 0.22, accuracy: 0.001)
        XCTAssertTrue(encoding.estimatedSizeText(duration: 150).contains("–"))
    }

    func testWebSizeEstimateIsASingleNumber() {
        let encoding = ExportVideoQuality.web.encodingProfile(
            baseBitrate: 8_000_000,
            framesPerSecond: 30,
            audioBitrate: 192_000
        )
        XCTAssertEqual(encoding.estimatedSizeCaption, "Estimated size")
        XCTAssertFalse(encoding.estimatedSizeText(duration: 150).contains("–"))
    }
}
