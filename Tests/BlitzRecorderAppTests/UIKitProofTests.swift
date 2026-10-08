import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class UIKitProofTests: XCTestCase {
    @MainActor
    func testUIKitRenders() async throws {
        guard let output = ProcessInfo.processInfo.environment["BLITZRECORDER_EXPORT_UI_PROOF"] else {
            throw XCTSkip("Provide a proof output directory.")
        }
        let width: CGFloat = 1180
        let updates = BlitzUIKitView.demoUpdates()
        for (index, section) in BlitzUIKitContent.sections.enumerated() {
            let page = section.1
                .padding(32)
                .frame(width: width, alignment: .leading)
                .background(BlitzUI.panelBackground)
                .foregroundStyle(BlitzUI.primaryText)
                .environmentObject(updates)
                .preferredColorScheme(.dark)
            let controller = NSHostingController(rootView: page)
            let height = controller.sizeThatFits(in: CGSize(width: width, height: 100_000)).height
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentViewController = controller
            window.setContentSize(CGSize(width: width, height: height))
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(700))
            let host = controller.view
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: URL(fileURLWithPath: output).appendingPathComponent(String(format: "ui-kit-%02d-%@.png", index, section.0)))
            window.orderOut(nil)
            window.contentViewController = nil
        }
    }
}
