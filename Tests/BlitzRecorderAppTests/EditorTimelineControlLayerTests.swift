import AppKit
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class EditorTimelineControlLayerTests: XCTestCase {
    @MainActor
    func testForegroundControlsLeaveTheRestOfTheTimelineClickable() async throws {
        let hover = EditorTimelineRulerHover()
        hover.position = 70
        let host = NSHostingView(rootView: HitTestFixture().overlay { EditorTimelineHoverLine(hover: hover) })
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 180)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        for target in [(x: 70.0, y: 75.0, id: "control"), (x: 170.0, y: 75.0, id: "timeline"),
                       (x: 70.0, y: 60.0, id: "timeline")] {
            let point = NSPoint(x: target.x, y: target.y)
            let hitPoint = host.superview?.convert(point, from: host) ?? point
            let view = host.hitTest(hitPoint)
            XCTAssertEqual(view?.identifier?.rawValue, target.id)
        }
    }

    @MainActor
    func testSelectionOutlineLeavesOnlyTheClipTrimGripInteractive() async throws {
        let host = NSHostingView(rootView: SelectedClipFixture().preferredColorScheme(.dark))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 180)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let grip = try sample(.init(bitmap: bitmap, x: 78, y: 32))
        XCTAssertGreaterThan(grip.redComponent, 0.6)
        XCTAssertGreaterThan(grip.blueComponent, 0.6)
        for y: CGFloat in [85, 128, 160] {
            let color = try sample(.init(bitmap: bitmap, x: 78, y: y))
            XCTAssertLessThan(color.redComponent, 0.15)
            let point = NSPoint(x: 78, y: y)
            let hitPoint = host.superview?.convert(point, from: host) ?? point
            XCTAssertEqual(host.hitTest(hitPoint)?.identifier?.rawValue, "timeline")
        }
    }

    @MainActor
    func testRulerHoverGuideMovesWithoutMovingThePlayheadAndClearsOnExit() async throws {
        let hover = EditorTimelineRulerHover()
        let fixture = ZStack(alignment: .topLeading) {
            Color.black
            Rectangle().fill(.green).frame(width: 4).offset(x: 38)
            EditorTimelineHoverLine(hover: hover)
        }
        let host = NSHostingView(rootView: fixture.preferredColorScheme(.dark))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 180)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        let ruler = CGRect(x: 20, y: 0, width: 220, height: 30)
        for x: CGFloat? in [70, 120, nil] {
            hover.update(.init(location: x.map { CGPoint(x: $0 + 20, y: 15) }, ruler: ruler, isInteractive: true))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let playhead = try sample(.init(bitmap: bitmap, x: 40, y: 80))
            XCTAssertGreaterThan(playhead.greenComponent, playhead.redComponent * 2)
            for target: CGFloat in [70, 120] {
                let color = try sample(.init(bitmap: bitmap, x: target, y: 80))
                if x == target {
                    XCTAssertGreaterThan(color.redComponent, 0.4)
                    XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.02)
                } else {
                    XCTAssertLessThan(color.redComponent, 0.05)
                }
            }
        }
    }

    @MainActor
    func testSilenceMarksFollowCutsAndScrollWithoutHidingWaveformsOrBlockingSelection() async throws {
        for marksSilence in [true, false] {
            let host = NSHostingView(rootView: SilenceFixture(marksSilence: marksSilence).preferredColorScheme(.dark))
            host.frame = NSRect(x: 0, y: 0, width: 220, height: 180)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            for y: CGFloat in [20, 149] {
                let silence = try sample(.init(bitmap: bitmap, x: 80, y: y))
                if marksSilence {
                    XCTAssertGreaterThan(silence.redComponent, 0.15)
                    XCTAssertGreaterThan(silence.redComponent, silence.greenComponent * 2)
                } else {
                    XCTAssertLessThan(silence.redComponent, 0.05)
                }
            }
            for point in [CGPoint(x: 40, y: 20), CGPoint(x: 80, y: 85), CGPoint(x: 80, y: 103)] {
                let color = try sample(.init(bitmap: bitmap, x: point.x, y: point.y))
                XCTAssertLessThan(color.redComponent, 0.05)
            }
            let waveform = try sample(.init(bitmap: bitmap, x: 80, y: 128))
            XCTAssertGreaterThan(waveform.redComponent, 0.6)
            XCTAssertGreaterThan(waveform.greenComponent, 0.5)
            let point = NSPoint(x: 80, y: 128)
            let hitPoint = host.superview?.convert(point, from: host) ?? point
            XCTAssertEqual(host.hitTest(hitPoint)?.identifier?.rawValue, "timeline")
        }
    }

    @MainActor
    func testGripRemainsAboveSelectionAndPlayheadAfterTranslation() async throws {
        for offset: CGFloat in [0, -30, 65] {
            let fixture = ControlFixture(offset: offset, viewportTop: 30)
            let bitmap = try await render(fixture)
            let color = try sample(.init(bitmap: bitmap, x: 70 + offset, y: 68))
            XCTAssertGreaterThan(color.redComponent, color.greenComponent * 2)
            XCTAssertGreaterThan(color.redComponent, color.blueComponent * 2)
        }
    }

    @MainActor
    func testControlLayerClipsGripsOutsideTheTrackViewport() async throws {
        let bitmap = try await render(ControlFixture(offset: 0, viewportTop: 70))
        let clipped = try sample(.init(bitmap: bitmap, x: 70, y: 66))
        let visible = try sample(.init(bitmap: bitmap, x: 70, y: 72))
        XCTAssertGreaterThan(clipped.greenComponent, clipped.redComponent * 2)
        XCTAssertGreaterThan(visible.redComponent, visible.greenComponent * 2)
    }

    @MainActor
    private func render(_ fixture: ControlFixture) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: fixture.preferredColorScheme(.dark))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 180)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["BLITZ_TIMELINE_RENDER_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(
                "timeline-grip-\(Int(fixture.offset))-\(Int(fixture.viewportTop)).png")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        }
        return bitmap
    }

    private struct Sample {
        let bitmap: NSBitmapImageRep
        let x: CGFloat
        let y: CGFloat
    }

    private func sample(_ request: Sample) throws -> NSColor {
        try XCTUnwrap(request.bitmap.colorAt(
            x: Int(request.x * CGFloat(request.bitmap.pixelsWide) / 220),
            y: Int(request.y * CGFloat(request.bitmap.pixelsHigh) / 180))?.usingColorSpace(.deviceRGB))
    }
}

private struct HitTarget: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(name)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct HitTestFixture: View {
    var body: some View {
        HitTarget(name: "timeline")
            .overlay(alignment: .topLeading) {
                HitTarget(name: "control")
                    .frame(width: 12, height: 64)
                    .timelineControl(id: "control")
                    .offset(x: 64, y: 36)
            }
            .overlayPreferenceValue(EditorTimelineControlKey.self) { controls in
                GeometryReader { geometry in
                    EditorTimelineControlLayer(configuration: .init(
                        controls: controls, geometry: geometry,
                        viewport: CGRect(x: 20, y: 70, width: 180, height: 110)))
                }
            }
    }
}

private struct ControlFixture: View {
    let offset: CGFloat
    let viewportTop: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            EditorTimelineGrip(tint: .red, isActive: true)
                .frame(width: 12, height: 64)
                .timelineControl(id: "grip")
                .offset(x: 64 + offset, y: 36)
            Rectangle()
                .fill(.green)
                .frame(width: 4, height: 180)
                .offset(x: 68 + offset)
        }
        .overlayPreferenceValue(EditorTimelineControlKey.self) { controls in
            GeometryReader { geometry in
                EditorTimelineControlLayer(configuration: .init(
                    controls: controls, geometry: geometry,
                    viewport: CGRect(x: 20, y: viewportTop, width: 180, height: 180 - viewportTop)))
            }
        }
    }
}

private struct SilenceFixture: View {
    let marksSilence: Bool

    private let projection = EditorTimelineProjection(.init(duration: 10, cuts: [
        .init(start: 2, end: 4, kind: .manual, source: .user)
    ]))
    private let viewport = EditorTimelineViewport(lowerBound: 20, upperBound: 240)

    var body: some View {
        HitTarget(name: "timeline")
            .background(.black)
            .overlay(alignment: .topLeading) {
                EditorTimelineMediaCanvas(
                    frames: [], waveform: EditorAudioWaveform(.init(peaks: Array(repeating: 0.5, count: 100))),
                    isVideo: false, tint: .white, projection: projection,
                    sourceDuration: 10, sourceOffset: 0, pixelsPerSecond: 20, viewport: viewport)
                    .frame(width: 220, height: 44)
                    .offset(x: -viewport.lowerBound, y: 106)
            }
            .overlay {
                EditorTimelineSilenceOverlay(configuration: .init(
                    segments: SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
                        .init(start: 6, end: 8, kind: .silence, source: .automatic, isEnabled: marksSilence)
                    ])),
                    projection: projection, pixelsPerSecond: 20, viewport: viewport, rows: [0..<64, 106..<150]))
            }
    }
}

private struct SelectedClipFixture: View {
    private let projection = EditorTimelineProjection(.init(duration: 10, cuts: []))

    var body: some View {
        HitTarget(name: "timeline")
            .background(.black)
            .overlay(alignment: .topLeading) {
                EditorVideoClipStrip(configuration: .init(
                    layout: .init(.init(projection: projection, splits: [4])),
                    viewport: .init(lowerBound: 0, upperBound: 220), pixelsPerSecond: 20,
                    width: 220, height: 64, edits: .empty, duration: 10,
                    selectedRanges: [.init(start: 0, end: 4)], hoveredRange: nil, trimOrigin: nil,
                    onSelect: { _ in }, onHover: { _ in }, onBeginTrim: { _ in }, onTrim: { _ in },
                    onEndTrim: {}, onCancelTrim: {}))
                    .frame(width: 220, height: 64)
            }
            .overlay(alignment: .topLeading) {
                EditorTimelineRangeHighlight(configuration: .init(
                    range: .init(start: 0, end: 4), projection: projection, pixelsPerSecond: 20,
                    height: 180, tint: BlitzUI.mint))
            }
            .overlayPreferenceValue(EditorTimelineControlKey.self) { controls in
                GeometryReader { geometry in
                    EditorTimelineControlLayer(configuration: .init(
                        controls: controls, geometry: geometry,
                        viewport: CGRect(x: 0, y: 0, width: 220, height: 180)))
                }
            }
    }
}
