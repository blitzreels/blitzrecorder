@testable import BlitzRecorderApp
import XCTest

final class ExportPerformanceProfileTests: XCTestCase {
    func testSharingProfilePreservesScreenDetailAndCreativeEffects() {
        let profile = profile(.fast)
        var settings = RecordingSettings()
        settings.screenShadowEnabled = true
        settings.cameraShadowEnabled = true
        let appliedSettings = profile.applying(to: settings)
        let appliedScene = profile.applying(to: RecordingScene(settings: settings))

        XCTAssertEqual(profile.resolution, .p1080)
        XCTAssertEqual(profile.framesPerSecond, 30)
        XCTAssertEqual(profile.videoQuality, .web)
        XCTAssertEqual(appliedSettings.exportEncoding?.codec, .h264)
        XCTAssertEqual(appliedSettings.finalVideoBitrate, 5_000_000)
        XCTAssertEqual(appliedSettings.finalAudioBitrate, 160_000)
        XCTAssertTrue(appliedSettings.screenShadowEnabled)
        XCTAssertTrue(appliedSettings.cameraShadowEnabled)
        XCTAssertTrue(appliedScene.screenShadowEnabled)
        XCTAssertTrue(appliedScene.cameraShadowEnabled)
    }

    func testBalancedProfileUses1080pAtSourceFrameRate() {
        let profile = profile(.balanced)

        XCTAssertEqual(profile.resolution, .p1080)
        XCTAssertEqual(profile.framesPerSecond, 60)
        XCTAssertEqual(profile.videoQuality, .high)
    }

    func testMaximumProfilePreservesSourceDimensionsAndFrameRate() {
        let profile = profile(.maximum)

        XCTAssertEqual(profile.resolution, .p2160)
        XCTAssertEqual(profile.framesPerSecond, 60)
        XCTAssertEqual(profile.videoQuality, .maximum)
    }

    func testCustomProfilePreserves24FPSAndAppliesBitrateAfterResolution() {
        let profile = ExportPerformanceProfile.resolved(
            preset: .custom,
            sourceResolution: .p2160,
            sourceFramesPerSecond: 60,
            customResolution: .p1440,
            customFramesPerSecond: 24,
            customVideoQuality: .high
        )
        let settings = profile.applying(to: RecordingSettings())

        XCTAssertEqual(profile.framesPerSecond, 24)
        XCTAssertEqual(settings.outputResolution, .p1440)
        XCTAssertEqual(settings.framesPerSecond, 24)
        XCTAssertEqual(settings.finalVideoBitrate, 17_500_000)
        XCTAssertEqual(settings.exportEncoding?.codec, .hevc)
        XCTAssertNil(settings.exportEncoding?.quality)
        XCTAssertEqual(settings.exportEncoding?.usesAverageBitRate, true)
    }

    func testBalancedProfilePreserves24FPSSource() {
        let profile = ExportPerformanceProfile.resolved(
            preset: .balanced,
            sourceResolution: .p1080,
            sourceFramesPerSecond: 24,
            customResolution: .p1080,
            customFramesPerSecond: 30,
            customVideoQuality: .high
        )

        XCTAssertEqual(profile.framesPerSecond, 24)
    }

    func testSharingProfileAppliesHighDetailH264Encoding() {
        let settings = profile(.fast).applying(to: RecordingSettings())

        XCTAssertEqual(settings.outputResolution, .p1080)
        XCTAssertEqual(settings.framesPerSecond, 30)
        XCTAssertEqual(settings.exportEncoding?.codec, .h264)
        XCTAssertEqual(settings.finalVideoBitrate, 5_000_000)
        XCTAssertEqual(settings.finalAudioBitrate, 160_000)
        XCTAssertNil(settings.exportEncoding?.quality)
        XCTAssertTrue(settings.exportEncoding?.prioritizesSpeed ?? false)
        XCTAssertFalse(settings.exportEncoding?.prefersFullRangeRGB ?? true)
    }

    func testSmallCustomProfileIsTwoAndAHalfMegabitsAt1080p30() {
        let settings = ExportPerformanceProfile.resolved(
            preset: .custom,
            sourceResolution: .p1080,
            sourceFramesPerSecond: 30,
            customResolution: .p1080,
            customFramesPerSecond: 30,
            customVideoQuality: .compact
        ).applying(to: RecordingSettings())

        XCTAssertEqual(settings.exportEncoding?.codec, .hevc)
        XCTAssertEqual(settings.finalVideoBitrate, 2_500_000)
        XCTAssertEqual(settings.finalAudioBitrate, 96_000)
    }

    func testArchivePresetAppliesHighHEVCAtSourceResolution() {
        let settings = profile(.maximum).applying(to: RecordingSettings())

        XCTAssertEqual(settings.outputResolution, .p2160)
        XCTAssertEqual(settings.exportEncoding?.codec, .hevc)
        XCTAssertNil(settings.exportEncoding?.quality)
        XCTAssertEqual(settings.exportEncoding?.usesAverageBitRate, true)
        XCTAssertTrue(settings.exportEncoding?.prefersFullRangeRGB ?? false)
    }

    func testMasterPresetUsesProResAtSourceResolution() {
        let profile = profile(.master)
        var settings = RecordingSettings()
        settings.outputVideoFormat = .mp4
        settings.layout = .horizontal
        let applied = profile.applying(to: settings)

        XCTAssertEqual(profile.resolution, .p2160)
        XCTAssertEqual(profile.framesPerSecond, 60)
        XCTAssertEqual(profile.videoQuality, .proRes)
        XCTAssertEqual(applied.outputVideoFormat, .mov)
        XCTAssertEqual(applied.exportEncoding?.codec, .proRes422)
    }

    func testProResCustomProfileForcesQuickTimeAndMezzanineRate() {
        var settings = RecordingSettings()
        settings.outputVideoFormat = .mp4
        settings.layout = .horizontal
        let applied = ExportPerformanceProfile.resolved(
            preset: .custom,
            sourceResolution: .p1080,
            sourceFramesPerSecond: 30,
            customResolution: .p1080,
            customFramesPerSecond: 30,
            customVideoQuality: .proRes
        ).applying(to: settings)

        XCTAssertEqual(applied.outputVideoFormat, .mov)
        XCTAssertEqual(applied.exportEncoding?.codec, .proRes422)
        XCTAssertEqual(applied.finalVideoBitrate, 147_000_000)
        XCTAssertEqual(applied.finalAudioBitrate, 320_000)
    }

    private func profile(_ preset: ExportPerformancePreset) -> ExportPerformanceProfile {
        ExportPerformanceProfile.resolved(
            preset: preset,
            sourceResolution: .p2160,
            sourceFramesPerSecond: 60,
            customResolution: .p720,
            customFramesPerSecond: 30,
            customVideoQuality: .standard
        )
    }
}
