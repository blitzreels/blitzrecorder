import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class BottomDockLayoutQATests: XCTestCase {
    private static let widths: [CGFloat] = [480, 560, 640, 720, 860, 1000, 1200]
    private static let states: [RecordingState] = [.idle, .recording, .paused]
    private static let gutter: CGFloat = 14
    private static let recordButtonMinWidth = 36

    @MainActor
    func testRecordButtonStaysInsideDockAtEveryWidth() async throws {
        let suite = "BottomDockLayoutQA.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        let output = ProcessInfo.processInfo.environment["BLITZRECORDER_DOCK_QA_OUTPUT"].map(URL.init(fileURLWithPath:))

        for state in Self.states {
            vm.state = state
            for width in Self.widths {
                let name = "\(state)-\(Int(width))"
                let bitmap = try await render(vm: vm, width: width)
                if let output {
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: output.appendingPathComponent("dock-\(name).png"))
                }
                let scale = CGFloat(bitmap.pixelsWide) / width
                let red = try XCTUnwrap(recordRedColumns(bitmap), "\(name): record button not rendered")
                XCTAssertGreaterThanOrEqual(red.count, Int(CGFloat(Self.recordButtonMinWidth) * scale),
                    "\(name): record button squeezed to \(red.count)px")
                XCTAssertLessThanOrEqual(CGFloat(red.upperBound), (width - Self.gutter) * scale,
                    "\(name): record button runs past the dock edge")
            }
        }
    }

    @MainActor
    private func render(vm: RecorderViewModel, width: CGFloat) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: BottomDock(vm: vm)
            .padding(.horizontal, Self.gutter)
            .frame(width: width)
            .background(Color.black)
            .preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 160),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func recordRedColumns(_ bitmap: NSBitmapImageRep) -> Range<Int>? {
        let rows = stride(from: 0, to: bitmap.pixelsHigh, by: 2)
        let columns = (0..<bitmap.pixelsWide).filter { x in
            rows.contains { y in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return color.redComponent > 0.75 && color.greenComponent < 0.4 && color.blueComponent < 0.4
            }
        }
        guard let first = columns.first, let last = columns.last else { return nil }
        let longestRun = columns.reduce(into: (start: first, previous: first - 1, best: first..<first)) { run, x in
            if x != run.previous + 1 { run.start = x }
            run.previous = x
            if x + 1 - run.start > run.best.count { run.best = run.start..<(x + 1) }
        }
        return last >= first ? longestRun.best : nil
    }
}
