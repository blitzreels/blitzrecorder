import AppKit
import Observation
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class EditorTimelineLiveTrimTests: XCTestCase {
    func testHeldTrimRevealsFootageAndPushesNeighborsBeforeOneCommit() async throws {
        for edge in [EditorClipTrimSession.Edge.right, .left] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var settings = RecordingSettings()
            settings.outputDirectory = directory
            let store = TakeFileStore()
            let take = try store.createTake(settings: settings)
            var project = try store.loadRecordingProject(at: take.projectURL)
            var edits = TimelineEdits.empty
            edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
            edits.videoSplits = [10]
            project.timelineEdits = .init(edits)
            let model = LiveTrimModel(project: project)
            let start = edge == .right ? 0.0 : 7.0
            let id = EditorVideoClipLayout.Clip.ID(takeStart: start)
            let gripID = "trim-\(id.ticks)-\(edge.rawValue)"
            let host = NSHostingView(rootView: LiveTrimFixture(model: model).preferredColorScheme(.dark))
            host.frame = CGRect(x: 0, y: 0, width: 1100, height: 400)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.orderOut(nil); window.contentView = nil; model.playback.teardown() }
            window.orderFront(nil)
            try await settle(host)
            let grip = try XCTUnwrap(model.controls[gripID])
            let firstLeft = try XCTUnwrap(model.controls["trim-0-left"])
            let firstRight = try XCTUnwrap(model.controls["trim-0-right"])
            let scale = (firstRight.maxX - firstLeft.minX) / 4
            let neighbor = try XCTUnwrap(model.controls["trim-6000-left"])
            try assertBoundary(.init(host: host, point: CGPoint(x: neighbor.minX, y: neighbor.minY + 8)))
            let anchor = CGPoint(x: grip.midX, y: grip.midY)
            try send(.init(window: window, host: host, point: anchor, type: .leftMouseDown))
            let delta = scale * (edge == .right ? 2 : -2)
            let end = CGPoint(x: anchor.x + delta, y: anchor.y)
            try send(.init(window: window, host: host, point: end, type: .leftMouseDragged))
            try await settle(host)

            XCTAssertEqual(model.commits.count, 0)
            XCTAssertEqual(model.project.edits, edits)
            let moved = try XCTUnwrap(model.controls[gripID])
            XCTAssertEqual(moved.minX, grip.minX + delta, accuracy: 1)
            try assertBoundary(.init(host: host, point: CGPoint(x: neighbor.minX + abs(delta), y: neighbor.minY + 8)))

            try send(.init(window: window, host: host, point: anchor, type: .leftMouseDragged))
            try await settle(host)
            XCTAssertEqual(model.commits.count, 0)
            XCTAssertEqual(try XCTUnwrap(model.controls[gripID]).minX, grip.minX, accuracy: 1)
            try assertBoundary(.init(host: host, point: CGPoint(x: neighbor.minX, y: neighbor.minY + 8)))
            try send(.init(window: window, host: host, point: end, type: .leftMouseDragged))
            try await settle(host)
            XCTAssertEqual(model.commits.count, 0)
            try send(.init(window: window, host: host, point: end, type: .leftMouseUp))
            try await settle(host)
            XCTAssertEqual(model.commits.count, 1)
            XCTAssertEqual(EditorTimelineProjection(.init(duration: 14, cuts: model.project.edits.cuts)).duration,
                13, accuracy: 0.02)
        }
    }

    private struct MouseRequest {
        let window: NSWindow
        let host: NSView
        let point: CGPoint
        let type: NSEvent.EventType
    }

    private func send(_ request: MouseRequest) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: request.type, location: request.host.convert(request.point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: request.window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: request.type == .leftMouseUp ? 0 : 1))
        request.window.sendEvent(event)
    }

    private func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }

    private struct BoundaryRequest {
        let host: NSView
        let point: CGPoint
    }

    private func assertBoundary(_ request: BoundaryRequest) throws {
        let bitmap = try XCTUnwrap(request.host.bitmapImageRepForCachingDisplay(in: request.host.bounds))
        request.host.cacheDisplay(in: request.host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / request.host.bounds.width
        let center = Int(request.point.x * scale)
        let y = Int(request.point.y * CGFloat(bitmap.pixelsHigh) / request.host.bounds.height)
        func brightness(_ x: Int) throws -> CGFloat {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
            return color.redComponent + color.greenComponent + color.blueComponent
        }
        let radius = Int(3 * scale)
        let values = try (center - radius...center + radius).map { try brightness($0) }
        let darkest = try XCTUnwrap(values.min())
        let adjacent = try min(brightness(center - Int(8 * scale)), brightness(center + Int(8 * scale)))
        XCTAssertGreaterThan(adjacent - darkest, 0.04)
    }

}

@MainActor
@Observable
private final class LiveTrimModel {
    var project: RecordingProject
    var controls: [String: CGRect] = [:]
    var commits: [TimelineEdits] = []
    var selection: EditorSelection?
    var zoom = 1.0
    var showsShortcuts = false
    var showsSourceTracks = false
    let playback = EditorPlaybackController()
    let library = EditorMediaLibrary()
    let silence = SilenceEditingSession()

    init(project: RecordingProject) { self.project = project }

    func commit(_ edits: TimelineEdits) {
        commits.append(edits)
        project.timelineEdits = .init(edits)
    }
}

private struct LiveTrimFixture: View {
    @Bindable var model: LiveTrimModel

    var body: some View {
        EditorTimelineView(
            project: model.project, transcript: nil, transcriptionStatus: .notGenerated,
            onGenerateTranscript: {}, assets: [], library: model.library, draftScene: nil, draftSceneEventIndex: nil,
            duration: 14, playback: model.playback, selection: $model.selection, onSeek: { _ in }, onSeekEnded: {},
            onTogglePlayback: {}, onPlaybackRateChange: { _ in }, isInteractive: true,
            hiddenAssetIDs: [], mutedAssetIDs: [], toggleableAssetIDs: [], onToggleTrack: { _ in },
            onSplit: {}, onDeleteSelection: {}, deleteAction: nil, onDeleteSegment: {}, canDeleteSegment: false,
            onJoinSegment: {}, onRestoreRange: {}, onTrimClip: model.commit, onMarkIn: {}, onMarkOut: {},
            zoomLevel: $model.zoom, showsShortcuts: $model.showsShortcuts, showsSourceTracks: $model.showsSourceTracks,
            silence: model.silence, onOpenSilence: {}, onChangePlacedItem: { _ in }, onRemovePlacedItem: { _ in }
        )
        .overlayPreferenceValue(EditorTimelineControlKey.self) { controls in
            GeometryReader { geometry in
                let frames = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, geometry[$0.bounds]) })
                Color.clear
                    .allowsHitTesting(false)
                    .onChange(of: frames, initial: true) { _, frames in model.controls = frames }
            }
        }
    }
}
