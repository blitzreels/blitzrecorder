@testable import BlitzRecorderApp
import XCTest

final class ExportPerformanceProfileTests: XCTestCase {
    func testSmallerProfileUses1080p30AndPreservesCreativeEffects() {
        let profile = profile(.fast)
        var settings = RecordingSettings()
        settings.screenShadowEnabled = true
        settings.cameraShadowEnabled = true
        let appliedSettings = profile.applying(to: settings)
        let appliedScene = profile.applying(to: RecordingScene(settings: settings))

        XCTAssertEqual(profile.resolution, .p1080)
        XCTAssertEqual(profile.framesPerSecond, 30)
        XCTAssertEqual(profile.videoQuality, .standard)
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
        XCTAssertEqual(settings.finalVideoBitrate, settings.autoVideoBitrate)
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
