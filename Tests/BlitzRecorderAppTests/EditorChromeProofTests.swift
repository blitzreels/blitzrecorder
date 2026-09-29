import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class EditorChromeProofTests: XCTestCase {
    @MainActor
    func testInspectorTabsKeepOneRowWithDistinctSymbols() throws {
        let tabs: [EditorInspectorTab] = [.layout, .silence, .text, .zoom, .privacy, .audio]
        XCTAssertEqual(Set(tabs.map(\.systemImage)).count, tabs.count, "Each editor tool needs its own symbol.")
        for tab in tabs {
            XCTAssertNotNil(NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: nil), tab.rawValue)
        }
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in EditorInspectorTabBar(selection: .constant(tab)) }
        }
            .frame(width: 340).background(BlitzUI.panelBackground).preferredColorScheme(.dark))
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 340, accuracy: 1)
        guard let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_UI_PROOF"] else { return }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("inspector-tabs.png"))
    }
}
