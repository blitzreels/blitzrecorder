import XCTest
import AppKit
import SwiftUI

@testable import BlitzRecorderApp

final class EditorPaneSizingTests: XCTestCase {
    @MainActor
    func testSharingInspectorStaysBesideTheTimelineAtFullHeight() throws {
        for fullHeight in [true, false] {
            let host = NSHostingView(rootView: EditorWorkspaceSplitView(showsInspector: true,
                showsSourceTracks: true, inspectorSpansTimeline: fullHeight,
                preview: { Color(red: 1, green: 0, blue: 0) },
                inspector: { Color(red: 0, green: 0, blue: 1) },
                timeline: { Color(red: 0, green: 1, blue: 0) }).frame(width: 1200, height: 700))
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let edges = try [10, bitmap.pixelsHigh - 10].map { y in
                try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide - 10, y: y)?.usingColorSpace(.sRGB))
            }
            if let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_UI_PROOF"] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("workspace-\(fullHeight).png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            }
            XCTAssertEqual(edges.filter { $0.blueComponent > $0.greenComponent + 0.5 }.count,
                           fullHeight ? 2 : 1)
            XCTAssertEqual(edges.filter { $0.greenComponent > $0.blueComponent + 0.5 }.count,
                           fullHeight ? 0 : 1)
        }
    }

    func testInspectorBoundsPreservePreviewSpace() {
        let wide = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: 2_000, available: 1_200))
        XCTAssertEqual(wide.value, 640)
        let narrow = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: 2_000, available: 800))
        XCTAssertEqual(narrow.value, 432)
        XCTAssertGreaterThanOrEqual(800 - narrow.value - EditorPaneSizing.dividerSize, 360)
        XCTAssertEqual(EditorPaneSizing.resolve(.init(pane: .inspector, preferred: 0, available: 800)).value, 312)
    }

    func testTimelineBoundsLeaveSpaceForPreviewAndControls() {
        let expanded = EditorPaneSizing.resolve(.init(pane: .timeline, preferred: 900, available: 680))
        XCTAssertEqual(expanded.value, 472)
        XCTAssertEqual(680 - expanded.value - EditorPaneSizing.dividerSize, 200)
        let collapsed = EditorPaneSizing.resolve(.init(pane: .timeline, preferred: -50, available: 680))
        XCTAssertEqual(collapsed.value, 180)
    }

    func testTemporarilySmallWindowsDoNotLosePreferredSize() {
        let preferred = 500.0
        let small = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: preferred, available: 640))
        XCTAssertGreaterThan(small.value, 0)
        XCTAssertLessThan(small.value, 640 - EditorPaneSizing.dividerSize)
        XCTAssertEqual(small.bounds.lowerBound, small.bounds.upperBound)
        let restored = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: preferred, available: 1_400))
        XCTAssertEqual(restored.value, preferred)
    }

    func testInvalidPreferencesAndTransientGeometryStayFinite() {
        XCTAssertEqual(EditorPaneSizing.resolve(.init(pane: .inspector, preferred: .nan, available: 1_200)).value, 360)
        XCTAssertEqual(
            EditorPaneSizing.resolve(.init(pane: .timeline, preferred: .infinity, available: 680)).value, 380)
        for available in [0.0, -1, .nan, .infinity] {
            let sizing = EditorPaneSizing.resolve(.init(pane: .timeline, preferred: 300, available: available))
            XCTAssertEqual(sizing.value, 0)
            XCTAssertEqual(sizing.bounds, 0...0)
        }
    }
}
