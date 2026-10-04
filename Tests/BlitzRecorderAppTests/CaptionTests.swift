import AppKit
import AVFoundation
import SwiftUI
import XCTest
@testable import BlitzRecorderApp

final class CaptionTests: XCTestCase {
    func testGenerationUsesWordTimingAndBreaksAtPausesAndSpeakers() {
        let words: [TranscriptWord] = [
            .init(text: "Bonjour", startTime: 0.2, endTime: 0.6, confidence: 1, speakerID: "a"),
            .init(text: "tout", startTime: 0.6, endTime: 0.8, confidence: 1, speakerID: "a"),
            .init(text: "le monde!", startTime: 0.8, endTime: 1.3, confidence: 1, speakerID: "a"),
            .init(text: "Après", startTime: 3, endTime: 3.5, confidence: 1, speakerID: "a"),
            .init(text: "oui", startTime: 3.5, endTime: 4, confidence: 1, speakerID: "b")
        ]
        let cues = CaptionGenerator.cues(transcript(words))
        XCTAssertEqual(cues.map(\.text), ["Bonjour tout le monde!", "Après", "oui"])
        XCTAssertEqual(cues.first?.start, 0.2)
        XCTAssertEqual(cues.first?.end, 1.3)
        XCTAssertEqual(cues.first?.words, Array(words.prefix(3)))
    }

    func testLongSpeechBecomesReadablePhrasesWithoutLosingWords() {
        let words = (0..<100).map { TranscriptWord(text: "word\($0)", startTime: Double($0) * 0.3,
            endTime: Double($0 + 1) * 0.3, confidence: 1) }
        let cues = CaptionGenerator.cues(transcript(words))
        XCTAssertEqual(cues.flatMap(\.words), words)
        XCTAssertTrue(cues.allSatisfy { $0.text.count <= 42 && $0.end - $0.start <= 4.01 })
    }

    func testLegacySegmentCaptionsRemainWithinSegmentTiming() {
        var source = transcript([])
        source = RecordingTranscript(version: source.version, id: source.id, mediaPath: source.mediaPath,
            generatedAt: source.generatedAt, duration: 20, confidence: 1, text: "One two three four five six seven eight nine ten.",
            suggestedTitle: nil, speakers: [], segments: [
                .init(id: UUID(), speakerID: "a", startTime: 5, endTime: 15,
                      text: "One two three four five six seven eight nine ten.", confidence: 1)
            ])
        let cues = CaptionGenerator.cues(source)
        XCTAssertGreaterThan(cues.count, 1)
        XCTAssertEqual(cues.first?.start, 5)
        XCTAssertEqual(cues.last?.end, 15)
        XCTAssertEqual(cues.map(\.text).joined(separator: " "), source.text)
    }

    func testDeletedWordsDisappearAndTimingFollowsTheSameCutMapAsVideo() throws {
        let words = ["Keep", "remove", "this", "please"].enumerated().map {
            TranscriptWord(text: $0.element, startTime: Double($0.offset), endTime: Double($0.offset + 1), confidence: 1)
        }
        var track = CaptionTrack.empty
        track.isEnabled = true
        track.cues = CaptionGenerator.cues(transcript(words))
        let cuts: [TimelineCut] = [.init(start: 1, end: 3, kind: .manual, source: .user)]
        let captions = CaptionTimeline(.init(track: track, cuts: cuts))
        XCTAssertEqual(captions.cue(at: 0.5)?.text, "Keep")
        XCTAssertNil(captions.cue(at: 2))
        XCTAssertEqual(captions.cue(at: 3)?.text, "please")
        let map = TimelineTimeMap(takeDuration: .init(seconds: 4), cuts: cuts, playbackRate: 1.5)
        XCTAssertEqual(captions.cue(at: map.takeSeconds(forOutputSeconds: 1))?.text, "please")
        XCTAssertNil(captions.cue(at: 4))
        XCTAssertEqual(CaptionTimeline(.init(track: track, cuts: [])).cue(at: 2)?.text, "Keep remove this please")
        track.isEnabled = false
        XCTAssertTrue(CaptionTimeline(.init(track: track, cuts: cuts)).cues.isEmpty)
        XCTAssertFalse(track.cues.isEmpty)
    }

    func testOldProjectsDecodeWithoutCaptionsAndNewSettingsRoundTrip() throws {
        let legacy = Data(#"{"cuts":[],"textOverlays":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self, from: legacy).edits.captions, .empty)
        var edits = TimelineEdits.empty
        edits.captions.isEnabled = true
        edits.captions.style = .background
        edits.captions.position = .top
        edits.captions.shadow = false
        edits.captions.cues = [.init(id: UUID(), start: 1, end: 3, text: "A saved correction", words: [])]
        let snapshot = RecordingProject.TimelineEditsSnapshot(edits)
        XCTAssertFalse(snapshot.isEmpty)
        let decoded = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self,
            from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.edits.captions, edits.captions)
    }

    @MainActor
    func testCaptionsPersistWithUndoAndOutputVariants() throws {
        let fixture = try SyntheticRecording()
        let suite = "Captions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = RecorderViewModel(coordinator: RecorderCoordinator(
            accessController: AccessController(defaults: defaults), defaults: defaults), previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        vm.studioMode = .edit
        vm.lastExportedSourceTakeURL = fixture.take.scratchDirectory
        vm.lastExportedProject = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
        var edits = TimelineEdits.empty
        edits.captions.isEnabled = true
        edits.captions.cues = [.init(id: UUID(), start: 0, end: 3, text: "Local captions", words: [])]
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: edits, actionName: "Generate Captions")))
        XCTAssertEqual(try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL).edits.captions, edits.captions)
        XCTAssertEqual(vm.editorProject?.outputProject(for: .vertical).edits.captions, edits.captions)
        vm.undoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits.captions, .empty)
        vm.redoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits.captions, edits.captions)
    }

    func testSpritesScaleTo4KAndStayInsidePortraitAndLandscapeSafeAreas() throws {
        for canvas in [CGSize(width: 3840, height: 2160), CGSize(width: 2160, height: 3840), CGSize(width: 1080, height: 1080)] {
            for style in CaptionStyle.allCases {
                for position in CaptionPosition.allCases {
                    var track = CaptionTrack.empty
                    track.style = style
                    track.position = position
                    let sprite = try XCTUnwrap(CaptionRenderer.sprite(.init(.init(
                        cue: .init(id: UUID(), start: 0, end: 1, text: "Les sous-titres restent sur votre Mac.", words: []),
                        track: track, canvasSize: canvas))))
                    XCTAssertTrue(CGRect(origin: .zero, size: canvas).contains(sprite.frame))
                    XCTAssertLessThan(sprite.image.height, Int(canvas.height * 0.3))
                    XCTAssertGreaterThan(sprite.image.width, 50)
                    XCTAssertEqual(sprite.compositedImage(canvasSize: canvas).extent.minY,
                                   canvas.height - sprite.frame.maxY, accuracy: 0.01)
                }
            }
        }
    }

    func testRealExportCaptionsFollowCutsAndDisappearOutsideCue() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        var edits = TimelineEdits.empty
        edits.captions.isEnabled = true
        edits.captions.cues = [.init(id: UUID(), start: 0.5, end: 2.5, text: "Local captions", words: [])]
        edits.cuts = [.init(start: 1, end: 2, kind: .manual, source: .user)]
        let output = fixture.root.appendingPathComponent("captions.mov")
        let url = try await Merger.exportFinalVideo(.init(take: fixture.take, settings: fixture.settings,
            sceneEvents: [], backgroundMusic: nil, destinationURL: output, progressHandler: nil, timelineEdits: edits))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let before = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
        let during = try await generator.image(at: CMTime(seconds: 0.8, preferredTimescale: 600)).image
        let afterCut = try await generator.image(at: CMTime(seconds: 1.2, preferredTimescale: 600)).image
        let after = try await generator.image(at: CMTime(seconds: 1.8, preferredTimescale: 600)).image
        XCTAssertGreaterThan(whitePixels(during), whitePixels(before) + 100)
        XCTAssertGreaterThan(whitePixels(afterCut), whitePixels(before) + 100)
        XCTAssertLessThan(abs(whitePixels(after) - whitePixels(before)), 100)
    }

    private func whitePixels(_ image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        return bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).reduce(0) { count, i in
                count + (pixels[i] > 230 && pixels[i + 1] > 230 && pixels[i + 2] > 230 ? 1 : 0)
            }
        }
    }

    private func transcript(_ words: [TranscriptWord]) -> RecordingTranscript {
        .init(version: 1, id: UUID(), mediaPath: "/sample.mov", generatedAt: Date(), duration: 30,
            confidence: 1, text: CaptionGenerator.text(words), suggestedTitle: nil, speakers: [], segments: [], words: words)
    }
}
