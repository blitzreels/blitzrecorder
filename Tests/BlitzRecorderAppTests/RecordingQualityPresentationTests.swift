@testable import BlitzRecorderApp
import XCTest

final class RecordingQualityPresentationTests: XCTestCase {
    func testDefaultProfileSeparatesRecordingAndSourceMetadata() {
        let presentation = RecordingQualityPresentation(settings: RecordingSettings())

        XCTAssertEqual(presentation.compactLabel, "Recording · 1080p · 30 Source FPS")
        XCTAssertEqual(presentation.controlLabel, "1080p · 30 FPS")
        XCTAssertEqual(presentation.profileSummary, "1080p · 30 Source FPS · HEVC sources")
        XCTAssertEqual(presentation.sourceEncodingSummary, "HEVC · Screen 7.2 Mbps · Camera 6 Mbps")
    }

    func testCustomDetailExplainsExportAndSourceImpact() {
        var settings = RecordingSettings()
        settings.customVideoBitrate = 12_000_000

        let presentation = RecordingQualityPresentation(settings: settings)

        XCTAssertEqual(
            presentation.bitrateOverrideDetail,
            "Custom · Default export 12 Mbps · Source bitrates scale automatically"
        )
        XCTAssertEqual(presentation.sourceEncodingSummary, "HEVC · Screen 10.8 Mbps · Camera 9 Mbps")
    }
}
