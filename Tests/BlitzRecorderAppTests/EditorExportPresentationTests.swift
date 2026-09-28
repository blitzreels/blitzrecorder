import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class EditorExportPresentationTests: XCTestCase {
    func testSharingExportsOnlyTheVisibleFormatWithoutLosingAdditionalLocalChoices() {
        let request = EditorExportLayouts.Request(current: .vertical, additional: [.horizontal, .square])
        XCTAssertEqual(EditorExportDestination.link.layouts(request), [.vertical])
        XCTAssertEqual(Set(EditorExportDestination.file.layouts(request)), Set(CaptureLayout.allCases))
    }

    @MainActor
    func testBothExportDestinationsFitAndRemainVisible() throws {
        for destination in EditorExportDestination.allCases {
            let host = NSHostingView(rootView: EditorExportPopover(configuration: .init(
                destination: .constant(destination), additionalLayouts: .constant([]), currentLayout: .vertical,
                format: .constant(.mp4), resolution: .constant(.p1080), framesPerSecond: .constant(24),
                quality: .constant(.high), playbackRate: .constant(.init(clamping: 1.3)),
                estimatedSize: "≈ 160 MB", estimatedSizeCaption: "Estimated size", encodingDetail: "HEVC · 12 Mbps",
                directory: URL(fileURLWithPath: "/tmp/Recordings"), canExport: true,
                export: {}, chooseFolder: {}
            )))
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 380, accuracy: 1)
            XCTAssertLessThan(host.fittingSize.height, 600)
            if let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_UI_PROOF"] {
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let file = URL(fileURLWithPath: directory).appendingPathComponent("export-\(destination.rawValue).png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
            }
        }
    }

    func testProgressDoesNotRepeatItsTitleButKeepsUsefulDetails() {
        XCTAssertNil(EditorExportStatus.Progress(
            title: "Exporting MP4", percentage: "40%", detail: "Exporting MP4...", value: 0.4
        ).supplementaryDetail)
        XCTAssertEqual(EditorExportStatus.Progress(
            title: "Downloading iPhone Media", percentage: "40%", detail: "20 MB of 50 MB", value: 0.4
        ).supplementaryDetail, "20 MB of 50 MB")
    }

    func testCurrentCanvasAlwaysExportsWithOnlyTheRequestedAdditionalFormats() {
        let formats = CaptureLayout.allCases
        for current in formats {
            XCTAssertEqual(EditorExportLayouts.resolve(.init(current: current, additional: [])), [current])
            for mask in 0..<(1 << formats.count) {
                let additional = Set(formats.enumerated().compactMap { item in
                    mask & (1 << item.offset) == 0 ? nil : item.element
                })
                let selected = EditorExportLayouts.resolve(.init(current: current, additional: additional))
                XCTAssertEqual(Set(selected), additional.union([current]))
                XCTAssertEqual(selected.count, Set(selected).count)
            }
        }
    }

    func testDefaultExportKeepsSourceFrameRateAndHighQuality() {
        for fps in RecordingSettings.supportedFrameRates {
            let recipe = EditorExportRecipe.make(.init(
                preset: .balanced, sourceResolution: .p2160, sourceFramesPerSecond: fps,
                customResolution: .p720, customFramesPerSecond: 30, customVideoQuality: .compact,
                layout: .vertical, layoutCount: 1, audioBitrate: 192_000, duration: 60))
            XCTAssertEqual(recipe.profile.framesPerSecond, fps)
            XCTAssertEqual(recipe.profile.videoQuality, .high)
        }
    }

    @MainActor
    func testExportFieldsKeepTheSameSizeForEveryValue() {
        let fields = [
            ("File format", OutputVideoFormat.allCases.map(\.displayName)),
            ("Resolution", OutputResolution.allCases.map(\.displayName)),
            ("Export FPS", RecordingSettings.supportedFrameRates.map { "\($0)" })
        ]
        var heights: [CGFloat] = []
        for (title, values) in fields {
            for value in values {
                let host = NSHostingView(rootView: EditorExportChoiceRow(configuration: .init(
                    title: title, options: values, selection: .constant(value), label: { $0 }
                )).frame(width: 340))
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 340, accuracy: 1)
                heights.append(host.fittingSize.height)
            }
        }
        XCTAssertEqual(Set(heights).count, 1, "Changing export options must not shift adjacent rows.")
        XCTAssertEqual(heights.first, 38)
    }

    @MainActor
    func testExportSpeedSliderKeepsStableSizeAtEveryRate() {
        for rate in ExportPlaybackRate.all {
            let host = NSHostingView(rootView: EditorExportSpeedControl(selection: .constant(rate)).frame(width: 380))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 380, accuracy: 1)
            XCTAssertEqual(host.fittingSize.height, 34, accuracy: 1)
        }
    }

    @MainActor
    func testLongExportFilenameDoesNotStretchTheConfirmation() {
        let names = ["recording.mp4", String(repeating: "A long exported recording name ", count: 12) + ".mp4"]
        var heights: [CGFloat] = []
        for name in names {
            let host = NSHostingView(rootView: EditorExportStatusView(configuration: .init(
                status: .succeeded(URL(fileURLWithPath: "/tmp/recordings/\(name)")),
                open: { _ in }, reveal: { _ in }, share: { _ in }, sendToBlitzReels: { _ in }, retry: {}, dismiss: {}
            )).frame(width: 1120))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 1120, accuracy: 1)
            XCTAssertLessThanOrEqual(host.fittingSize.height, 80)
            heights.append(host.fittingSize.height)
        }
        XCTAssertEqual(Set(heights).count, 1)
    }
}
