import AVFoundation
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class EditorTrackVolumeTests: XCTestCase {
    func testOlderProjectsKeepOriginalLevelsAndInvalidValuesCannotBreakTheMix() throws {
        let decoded = try JSONDecoder().decode(RecordingProject.EditorStateSnapshot.self,
            from: Data(#"{"hiddenVideoSources":[],"mutedAudioSources":[]}"#.utf8))
        XCTAssertNil(decoded.audioLevels)
        var levels = EditorAudioLevels.unity
        levels.setVolume(.init(source: .microphone, volume: 0.35))
        levels.setVolume(.init(source: .microphone, volume: .nan))
        levels.setVolume(.init(source: .systemAudio, volume: -2))
        XCTAssertEqual(levels.volume(for: .microphone), 0.35)
        XCTAssertEqual(levels.volume(for: .systemAudio), 0)
        levels.setVolume(.init(source: .systemAudio, volume: 3))
        XCTAssertEqual(levels.volume(for: .systemAudio), 1)
    }

    func testTrackLevelsPreviewPersistUndoReopenAndExportAtTheSavedVolume() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 30))
        try writeTone(.init(url: fixture.take.audioURL, frequency: 440))
        try writeTone(.init(url: fixture.take.systemAudioURL, frequency: 880))
        var settings = fixture.settings
        settings.enabledSources = [.screen, .microphone, .systemAudio]
        settings.microphoneGain = 1.5
        settings.systemAudioGain = 0.8
        let store = TakeFileStore()
        let scenes = store.sceneEvents(from: try store.loadRecordingProject(at: fixture.take.projectURL))
        try store.writeRecordingProject(for: fixture.take, settings: settings, sceneEvents: scenes, finalVideoURL: nil)
        let suite = "EditorTrackVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let automatic = vm.transcriptionController.isAutomaticEnabled
        vm.transcriptionController.isAutomaticEnabled = false
        defer { vm.transcriptionController.isAutomaticEnabled = automatic; vm.prepareForWindowClose() }
        vm.settings = settings
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first))
        let original = try XCTUnwrap(vm.editorProject)
        let playback = EditorPlaybackController()
        defer { playback.teardown() }
        await playback.load(project: original, baseSettings: settings)
        XCTAssertTrue(playback.isReady)
        let videoPlayer = try XCTUnwrap(playback.videoPlayer(for: .screen))
        let fullOutput = fixture.root.appendingPathComponent("full.mp4")
        let quietOutput = fixture.root.appendingPathComponent("quiet.mp4")
        let profile = ExportPerformanceProfile.resolved(preset: .custom, sourceResolution: .p720,
            sourceFramesPerSecond: 30, customResolution: .p720, customFramesPerSecond: 30, customVideoQuality: .web)
        _ = try await coordinator.exportProjectForAgent(.init(
            projectURL: fixture.take.projectURL, outputFormat: .mp4, performanceProfile: profile,
            destinationURL: fullOutput, hiddenVideoSources: [], mutedAudioSources: [], backgroundMusic: nil))
        for source in [CaptureSource.microphone, .systemAudio] {
            let change = EditorTrackVolumeChange(source: source, volume: 0.25)
            playback.setTrackVolume(change)
            XCTAssertTrue(vm.changeEditorTrackVolume(change))
        }
        XCTAssertTrue(videoPlayer === playback.videoPlayer(for: .screen))
        XCTAssertEqual(playback.audioLevels.volume(for: .microphone), 0.25)
        var saved = try store.loadRecordingProject(at: fixture.take.projectURL)
        XCTAssertEqual(saved.editorState.audioLevels, playback.audioLevels)
        XCTAssertEqual(saved.settings, original.settings)
        vm.undoEditor()
        XCTAssertEqual(vm.editorProject?.editorState.audioLevels?.volume(for: .systemAudio), 1)
        vm.redoEditor()
        saved = try store.loadRecordingProject(at: fixture.take.projectURL)
        await playback.load(project: saved, baseSettings: settings)
        XCTAssertEqual(playback.audioLevels.volume(for: .microphone), 0.25)
        XCTAssertEqual(playback.audioLevels.volume(for: .systemAudio), 0.25)
        playback.setMuted(true, source: .microphone)
        playback.setMuted(false, source: .microphone)
        XCTAssertEqual(playback.audioLevels.volume(for: .microphone), 0.25)
        _ = try await coordinator.exportProjectForAgent(.init(
            projectURL: fixture.take.projectURL, outputFormat: .mp4, performanceProfile: profile,
            destinationURL: quietOutput, hiddenVideoSources: [], mutedAudioSources: [], backgroundMusic: nil))
        let fullLevel = try await level(fullOutput)
        let quietLevel = try await level(quietOutput)
        XCTAssertEqual(quietLevel - fullLevel, 20 * log10(0.25), accuracy: 0.4)
        let asset = AVURLAsset(url: quietOutput)
        let duration = try await asset.load(.duration)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.1)
        XCTAssertFalse(audioTracks.isEmpty)
        print("TRACK_VOLUME_EXPORT attenuation_db=\(quietLevel - fullLevel) duration=\(duration.seconds)")
    }

    private struct Tone {
        let url: URL
        let frequency: Double
    }

    private func writeTone(_ request: Tone) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for index in 0..<48_000 {
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * request.frequency / 48_000) * 0.2)
        }
        let file = try AVAudioFile(forWriting: request.url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000])
        try file.write(from: buffer)
    }

    private func level(_ url: URL) async throws -> Double {
        let windows = try await SilenceDetection.windows(.init(audioURL: url, takeDuration: 1, sourceOffset: 0,
            minimumSilence: 0.1, thresholdDB: -42, previousCuts: []))
        let middle = windows.filter { $0.start > 0.1 && $0.end < 0.9 }
        XCTAssertFalse(middle.isEmpty)
        return middle.reduce(0) { $0 + $1.decibels } / Double(max(1, middle.count))
    }
}
