import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class CaptionProofTests: XCTestCase {
    @MainActor
    func testCaptionStylesInNativeInspectorAnd4KExports() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZ_CAPTION_PROOF"] else {
            throw XCTSkip("Set BLITZ_CAPTION_PROOF to render local caption evidence.")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 45))
        let suite = "CaptionProof.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = RecorderViewModel(coordinator: RecorderCoordinator(
            accessController: AccessController(defaults: defaults), defaults: defaults), previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        vm.lastExportedSourceTakeURL = fixture.take.scratchDirectory
        var project = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
        var edits = TimelineEdits.empty
        edits.captions.isEnabled = true
        edits.captions.cues = [.init(id: UUID(), start: 0, end: 1.5,
            text: "Les sous-titres restent sur votre Mac.", words: [])]
        for style in CaptionStyle.allCases {
            edits.captions.style = style
            project.timelineEdits = .init(edits)
            vm.lastExportedProject = project
            var settings = fixture.settings
            settings.outputResolution = .p2160
            settings.framesPerSecond = 24
            settings.layout = style == .outline ? .horizontal : .vertical
            let url = try await Merger.exportFinalVideo(.init(take: fixture.take, settings: settings,
                sceneEvents: [], backgroundMusic: nil, destinationURL: TakeFileStore().uniqueFileURL(output.appendingPathComponent("\(style.rawValue)-4k.mov")),
                progressHandler: nil, timelineEdits: edits))
            let asset = AVURLAsset(url: url)
            let videos = try await asset.loadTracks(withMediaType: .video)
            let video = try XCTUnwrap(videos.first)
            let size = try await video.load(.naturalSize)
            XCTAssertEqual(min(size.width, size.height), 2160)
            let generator = AVAssetImageGenerator(asset: asset)
            let frame = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
            try save(.init(image: frame, url: output.appendingPathComponent("\(style.rawValue)-export.png")))
            let sprite = try XCTUnwrap(CaptionRenderer.sprite(.init(.init(cue: edits.captions.cues[0],
                track: edits.captions, canvasSize: size))))
            try save(.init(image: sprite.image, url: output.appendingPathComponent("\(style.rawValue)-sprite.png")))
            let host = NSHostingView(rootView: HStack(spacing: 0) {
                Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(BlitzUI.canvasBackground)
                VStack(spacing: 0) {
                    EditorInspectorTabBar(selection: .constant(.captions))
                    EditorCaptionsInspector(configuration: .init(vm: vm, playback: EditorPlaybackController(), transcript: nil))
                }.frame(width: 312).background(BlitzUI.panelBackground)
            }.frame(width: 1180, height: 850).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 850),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: output.appendingPathComponent("\(style.rawValue)-inspector.png"))
            window.contentView = nil
        }
    }

    private struct ImageOutput {
        let image: CGImage
        let url: URL
    }

    private func save(_ output: ImageOutput) throws {
        try XCTUnwrap(NSBitmapImageRep(cgImage: output.image).representation(using: .png, properties: [:])).write(to: output.url)
    }
}
