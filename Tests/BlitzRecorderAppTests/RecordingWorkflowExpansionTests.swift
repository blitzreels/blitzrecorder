import AVFoundation
import CoreImage
import XCTest
@testable import BlitzRecorderApp

final class RecordingWorkflowExpansionTests: XCTestCase {
    func testSquareDimensionsAndInsetKeepSourceShape() {
        for resolution in OutputResolution.allCases {
            let dimensions = resolution.dimensions(for: .square)
            XCTAssertEqual(dimensions.width, dimensions.height)
            XCTAssertEqual(dimensions.width, resolution.height)
        }
        let inset = SceneLayout.presetLayout(.cameraInset, for: .square)
        XCTAssertEqual(inset.cameraFrame.width / inset.cameraFrame.height, SceneLayout.cameraAspectRatio, accuracy: 0.001)
        XCTAssertTrue(ScenePreset.cameraInset.supports(.square))
        XCTAssertEqual(ScreenCaptureGeometry.previewDimensions(for: .square).width, 720)
    }

    func testMaskCoordinatesClampToSourceAndRespectTiming() {
        let frame = PrivacyMask.frame(.init(start: .init(x: 120, y: 60), end: .init(x: -10, y: 10), size: .init(width: 100, height: 100)))
        XCTAssertEqual(frame, CGRect(x: 0, y: 0.1, width: 1, height: 0.5))
        let mask = PrivacyMask(id: UUID(), source: .screen, frame: frame, start: 1, end: 3, style: .cover)
        XCTAssertFalse(mask.isVisible(at: 0.99))
        XCTAssertTrue(mask.isVisible(at: 1))
        XCTAssertFalse(mask.isVisible(at: 3))
    }

    func testCoverHidesOnlySelectedSourceRegion() {
        let image = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let mask = PrivacyMask(id: UUID(), source: .screen, frame: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), start: 0, end: 5, style: .cover)
        let covered = PrivacyMaskRenderer.render(.init(image: image, masks: [mask], source: .screen, time: 2))
        XCTAssertLessThan(pixel(.init(image: covered, point: .init(x: 20, y: 80))), 0.01)
        XCTAssertGreaterThan(pixel(.init(image: covered, point: .init(x: 20, y: 20))), 0.99)
        let camera = PrivacyMaskRenderer.render(.init(image: image, masks: [mask], source: .camera, time: 2))
        XCTAssertGreaterThan(pixel(.init(image: camera, point: .init(x: 20, y: 80))), 0.99)
    }

    func testLegacyEditsDecodeWithoutEnablingEffects() throws {
        let snapshot = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self, from: Data("{}".utf8))
        XCTAssertTrue(snapshot.edits.privacyMasks.isEmpty)
        XCTAssertEqual(snapshot.edits.voiceCleanup, .disabled)
        XCTAssertTrue(snapshot.edits.outputVariants.isEmpty)
        XCTAssertNil(snapshot.edits.activeOutputLayout)
    }

    func testOutputVariantsPersistWithoutChangingCaptureMetadata() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = RecordingSettings()
        settings.outputDirectory = directory
        settings.layout = .horizontal
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let original = try store.loadRecordingProject(at: take.projectURL)
        var edits = original.edits
        var square = RecordingOutputVariant.make(.init(project: original, layout: .square))
        let events = store.sceneEvents(from: original)
        if let first = events.first {
            var scene = first.scene
            scene.canvasPadding = 0.12
            square.scenes = [.init(.init(time: first.time, scene: scene, transition: first.transition))]
        }
        edits.outputVariants = [square]
        edits.activeOutputLayout = .square
        edits.privacyMasks = [.init(id: UUID(), source: .screen, frame: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.2), start: 0, end: 2, style: .cover)]
        edits.voiceCleanup.isEnabled = true
        edits.cuts = [.init(start: 1, end: 1.5, kind: .manual, source: .user)]
        _ = try store.updateProjectTimelineEdits(.init(projectURL: take.projectURL, edits: edits, baseSettings: settings))
        let saved = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(saved.settings, original.settings)
        XCTAssertEqual(saved.sceneEvents, original.sceneEvents)
        XCTAssertEqual(saved.outputProject.settings.layout, CaptureLayout.square.rawValue)
        XCTAssertEqual(saved.outputProject.timelineEdits.privacyMasks, edits.privacyMasks)
        XCTAssertEqual(saved.outputProject.edits.cuts, edits.cuts)
        XCTAssertEqual(saved.outputProject(for: .horizontal).settings, original.settings)
        XCTAssertEqual(saved.edits.voiceCleanup, edits.voiceCleanup)
    }

    func testTranscriptMatchesReturnTimestampsAndIgnoreDiacritics() {
        let segment = RecordingTranscript.Segment(id: UUID(), speakerID: "one", startTime: 12.5, endTime: 15,
                                                 text: "Le coût du café", confidence: 0.9)
        let transcript = RecordingTranscript(version: 1, id: UUID(), mediaPath: "/unused", generatedAt: Date(),
            duration: 20, confidence: 0.9, text: segment.text, suggestedTitle: nil, speakers: [], segments: [segment])
        let matches = ProjectTranscriptSearch.matches(.init(query: "cafe", transcript: transcript))
        XCTAssertEqual(matches.map(\.time), [12.5])
        XCTAssertTrue(ProjectTranscriptSearch.matches(.init(query: "not present", transcript: transcript)).isEmpty)
        XCTAssertTrue(ProjectTranscriptSearch.matches(.init(query: "   ", transcript: transcript)).isEmpty)
        XCTAssertNil(TitleGenerator.fallbackTitle(from: "Est que pas mais les des oui est que pas"))
    }

    func testDuckingSkipsRemovedSpeechAndUsesEditedTimes() {
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: [.init(start: 2, end: 5, kind: .manual, source: .user)])
        let ranges = MusicDucking.ranges(.init(windows: [
            .init(start: 3, end: 4, decibels: -15), .init(start: 6, end: 6.5, decibels: -20),
            .init(start: 7, end: 7.5, decibels: -70)
        ], threshold: -40, timeMap: map))
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start, 2.9, accuracy: 0.01)
        XCTAssertEqual(ranges[0].end, 3.8, accuracy: 0.01)
    }

    func testVoiceCleanupReducesNoiseAndPreservesSampleCountAndTiming() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.caf")
        let output = directory.appendingPathComponent("output.caf")
        let sampleRate = 24000.0
        let count = 72013
        let samples: [Float] = (0..<count).map { index in
            let time = Double(index) / sampleRate
            let noise = 0.02 * sin(2 * .pi * 90 * time)
            let speech = (time > 1 && time < 2) ? 0.2 * sin(2 * .pi * 700 * time) : 0
            return Float(noise + speech)
        }
        try writeAudio(.init(url: input, samples: samples, sampleRate: sampleRate))
        var settings = VoiceCleanupSettings()
        settings.isEnabled = true
        settings.strength = 1
        settings.normalizesSpeech = false
        try VoiceCleanupProcessor.processPCM(.init(source: input, destination: output, settings: settings))
        let file = try AVAudioFile(forReading: output)
        XCTAssertEqual(Int(file.length), count)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)))
        try file.read(into: buffer)
        let values = try XCTUnwrap(buffer.floatChannelData?[0])
        let quiet = (2400..<12000).reduce(0.0) { $0 + Double(values[$1] * values[$1]) }
        let originalQuiet = (2400..<12000).reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) }
        XCTAssertLessThan(quiet, originalQuiet * 0.5)
        let speech = (28000..<44000).reduce(0.0) { $0 + Double(values[$1] * values[$1]) }
        let originalSpeech = (28000..<44000).reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) }
        XCTAssertGreaterThan(speech, originalSpeech * 0.6)
        XCTAssertTrue((0..<count).allSatisfy { values[$0].isFinite && abs(values[$0]) <= 0.98 })
    }

    @MainActor
    func testCutInVariantPreservesBothTextLayoutsAndSupportsUndo() throws {
        let fixture = try SyntheticRecording()
        let store = TakeFileStore()
        let suite = "WorkflowVariantTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingSettingsStore.save(fixture.settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.studioMode = .edit
        vm.lastExportedSourceTakeURL = fixture.take.scratchDirectory
        vm.lastExportedProject = try store.loadRecordingProject(at: fixture.take.projectURL)
        var edits = try XCTUnwrap(vm.lastExportedProject?.edits)
        edits.textOverlays = [.init(start: 0, end: 3, text: "Landscape title",
            frame: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2), style: .title)]
        XCTAssertTrue(vm.applyOutputTextEdits(.init(edits: edits, actionName: "Add Title")))
        vm.selectOutputLayout(.square)
        edits = try XCTUnwrap(vm.editorProject?.edits)
        edits.textOverlays[0].text = "Square title"
        edits.textOverlays[0].frame.origin.y = 0.6
        XCTAssertTrue(vm.applyOutputTextEdits(.init(edits: edits, actionName: "Edit Square Title")))
        edits = try XCTUnwrap(vm.editorProject?.edits)
        edits.cuts = [.init(start: 1, end: 2, kind: .manual, source: .user)]
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: edits, actionName: "Cut Range")))
        var saved = try store.loadRecordingProject(at: fixture.take.projectURL)
        XCTAssertEqual(saved.edits.textOverlays.first?.text, "Landscape title")
        XCTAssertEqual(saved.outputProject.edits.textOverlays.first?.text, "Square title")
        XCTAssertEqual(saved.outputProject.edits.cuts.count, 1)
        vm.undoEditor()
        saved = try store.loadRecordingProject(at: fixture.take.projectURL)
        XCTAssertTrue(saved.edits.cuts.isEmpty)
        XCTAssertEqual(saved.outputProject.edits.textOverlays.first?.text, "Square title")
        vm.redoEditor()
        vm.selectOutputLayout(.horizontal)
        XCTAssertEqual(vm.editorProject?.edits.textOverlays.first?.text, "Landscape title")
        XCTAssertEqual(vm.editorProject?.edits.cuts.count, 1)
        vm.prepareForWindowClose()
    }

    @MainActor
    func testExportAllRatiosWithTimedMaskCleanupAndSharedCuts() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let sourceBefore = try Data(contentsOf: fixture.take.screenURL)
        let music = fixture.root.appendingPathComponent("music.caf")
        let musicFrequency = 2 * Double.pi * 220 / 48000
        let musicSamples: [Float] = (0..<144000).map { index in
            Float(0.15 * sin(Double(index) * musicFrequency))
        }
        try writeAudio(.init(url: music, samples: musicSamples, sampleRate: 48000))
        let pcm = fixture.root.appendingPathComponent("microphone.caf")
        try writeAudio(.init(url: pcm, samples: (0..<144000).map { index in
            let t = Double(index) / 48000
            return Float(0.01 * sin(t * 2 * .pi * 90) + (t > 1 ? 0.15 * sin(t * 2 * .pi * 700) : 0))
        }, sampleRate: 48000))
        let encoder = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: pcm), presetName: AVAssetExportPresetAppleM4A))
        try await encoder.export(to: fixture.take.audioURL, as: .m4a)
        let originalAudio = try Data(contentsOf: fixture.take.audioURL)
        var settings = fixture.settings
        settings.enabledSources = [.screen, .microphone]
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .horizontal)
        settings.canvasPadding = 0
        settings.screenCornerRadius = 0
        let store = TakeFileStore()
        try store.writeRecordingProject(for: fixture.take, settings: settings,
            sceneEvents: [.init(time: 0, scene: RecordingScene(settings: settings))], finalVideoURL: nil)
        var edits = TimelineEdits.empty
        edits.privacyMasks = [.init(id: UUID(), source: .screen,
            frame: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3), start: 1, end: 2, style: .cover)]
        edits.voiceCleanup.isEnabled = true
        edits.voiceCleanup.ducksMusic = true
        edits.cuts = [.init(start: 0.3, end: 0.7, kind: .manual, source: .user)]
        let project = try store.updateProjectTimelineEdits(.init(projectURL: fixture.take.projectURL, edits: edits, baseSettings: settings))
        for layout in CaptureLayout.allCases {
            let output = project.outputProject(for: layout)
            var renderSettings = store.recordingSettings(from: output, baseSettings: settings, outputFormat: .mov)
            renderSettings.layout = layout
            let destination = fixture.root.appendingPathComponent(layout.shortLabel.replacingOccurrences(of: ":", with: "-") + ".mov")
            let url = try await Merger.exportFinalVideo(.init(take: fixture.take, settings: renderSettings,
                sceneEvents: store.sceneEvents(from: output), backgroundMusic: .init(url: music, volume: 0.15), destinationURL: destination,
                progressHandler: nil, timelineEdits: output.edits))
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(duration, 2.6, accuracy: 0.08)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(videoTracks.first)
            let size = try await track.load(.naturalSize)
            let dimensions = settings.outputResolution.dimensions(for: layout)
            XCTAssertEqual(Int(size.width), dimensions.width)
            XCTAssertEqual(Int(size.height), dimensions.height)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let audio = try XCTUnwrap(audioTracks.first)
            let audioDuration = try await audio.load(.timeRange).duration.seconds
            XCTAssertEqual(audioDuration, duration, accuracy: 0.1)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let before = try await generator.image(at: TimelineTimeMap.time(0.1)).image
            let hidden = try await generator.image(at: TimelineTimeMap.time(1.1)).image
            let point = CGPoint(x: size.width / 2, y: size.height / 2)
            XCTAssertGreaterThan(pixel(.init(image: CIImage(cgImage: before), point: point)), 0.1)
            XCTAssertLessThan(pixel(.init(image: CIImage(cgImage: hidden), point: point)), 0.03)
            if let path = ProcessInfo.processInfo.environment["BLITZRECORDER_WORKFLOW_QA_DIR"] {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let retained = directory.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: retained.path) { try FileManager.default.removeItem(at: retained) }
                try FileManager.default.copyItem(at: url, to: retained)
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.take.screenURL), sourceBefore)
        XCTAssertEqual(try Data(contentsOf: fixture.take.audioURL), originalAudio)
        XCTAssertEqual(try store.loadRecordingProject(at: fixture.take.projectURL).settings.layout, CaptureLayout.horizontal.rawValue)
    }

    func testDuckingRampsRecoverAndFinishAtZero() {
        let mix = AVMutableAudioMixInputParameters()
        MusicDucking.apply(.init(parameters: mix, ranges: [.init(start: 1, end: 2), .init(start: 3.4, end: 4)],
                                volume: 0.8, duration: 4))
        var start: Float = 0
        var end: Float = 0
        var range = CMTimeRange.invalid
        XCTAssertTrue(mix.getVolumeRamp(for: TimelineTimeMap.time(1.5), startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(start, 0.2, accuracy: 0.001)
        XCTAssertEqual(end, 0.2, accuracy: 0.001)
        XCTAssertTrue(mix.getVolumeRamp(for: TimelineTimeMap.time(2.5), startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(start, 0.8, accuracy: 0.001)
        XCTAssertEqual(end, 0.8, accuracy: 0.001)
        XCTAssertTrue(mix.getVolumeRamp(for: TimelineTimeMap.time(3.99), startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(end, 0, accuracy: 0.001)
        XCTAssertLessThan(start, 0.1)
    }

    private struct PixelRequest { let image: CIImage; let point: CGPoint }
    private func pixel(_ request: PixelRequest) -> Float {
        var bytes = [Float](repeating: 0, count: 4)
        CIContext().render(request.image, toBitmap: &bytes, rowBytes: 16,
            bounds: CGRect(origin: request.point, size: .init(width: 1, height: 1)), format: .RGBAf,
            colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes[0]
    }

    private struct AudioRequest { let url: URL; let samples: [Float]; let sampleRate: Double }
    private func writeAudio(_ request: AudioRequest) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: request.sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: request.url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(request.samples.count)))
        buffer.frameLength = AVAudioFrameCount(request.samples.count)
        request.samples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: request.samples.count)
        }
        try file.write(from: buffer)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecorderWorkflowTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
