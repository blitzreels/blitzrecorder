import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class EditorExportPresentationTests: XCTestCase {
    func testProgressDoesNotRepeatItsTitleButKeepsUsefulDetails() {
        XCTAssertNil(EditorExportStatus.Progress(
            title: "Exporting MP4", percentage: "40%", detail: "Exporting MP4...", value: 0.4
        ).supplementaryDetail)
        XCTAssertEqual(EditorExportStatus.Progress(
            title: "Downloading iPhone Media", percentage: "40%", detail: "20 MB of 50 MB", value: 0.4
        ).supplementaryDetail, "20 MB of 50 MB")
    }

    @MainActor
    func testExportFieldsKeepTheSameSizeForEveryValue() {
        let fields = [
            ("Preset", ExportPerformancePreset.allCases.map(\.displayName)),
            ("Format", OutputVideoFormat.allCases.map(\.displayName)),
            ("Resolution", OutputResolution.allCases.map(\.displayName)),
            ("Export FPS", RecordingSettings.supportedFrameRates.map { "\($0) fps" }),
            ("Quality", ExportVideoQuality.menuCases.map(\.displayName)),
            ("Speed", ExportPlaybackRate.all.map(\.displayName))
        ]
        var heights: [CGFloat] = []
        for (title, values) in fields {
            for value in values {
                let host = NSHostingView(rootView: BlitzFormDropdown(configuration: .init(
                    title: title, selection: .constant(value),
                    options: values.map { .init(value: $0, title: $0, detail: nil) }
                )).frame(width: 380))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 380, accuracy: 1)
                heights.append(host.fittingSize.height)
            }
        }
        XCTAssertEqual(Set(heights).count, 1, "Changing export options must not shift adjacent rows.")
        XCTAssertEqual(heights.first, 34)
    }

    @MainActor
    func testLongExportFilenameDoesNotStretchTheConfirmation() {
        let names = ["recording.mp4", String(repeating: "A long exported recording name ", count: 12) + ".mp4"]
        var heights: [CGFloat] = []
        for name in names {
            let host = NSHostingView(rootView: EditorExportStatusView(configuration: .init(
                status: .succeeded(URL(fileURLWithPath: "/tmp/recordings/\(name)")),
                open: { _ in }, reveal: { _ in }, sendToBlitzReels: { _ in }, retry: {}, dismiss: {}
            )).frame(width: 1120))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 1120, accuracy: 1)
            XCTAssertLessThanOrEqual(host.fittingSize.height, 80)
            heights.append(host.fittingSize.height)
        }
        XCTAssertEqual(Set(heights).count, 1)
    }
}
