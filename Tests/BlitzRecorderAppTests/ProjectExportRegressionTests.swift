import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class ProjectExportRegressionTests: XCTestCase {
    func testRealProjectAtFractionalSpeed() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["BLITZ_EXPORT_TEST_PROJECT"],
              let outputPath = environment["BLITZ_EXPORT_TEST_OUTPUT"] else {
            throw XCTSkip("Set an isolated project copy and output path to validate a real export.")
        }
        let output = URL(fileURLWithPath: outputPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let store = TakeFileStore()
        let project = try store.loadRecordingProject(at: URL(fileURLWithPath: path))
        let outputProject = project.outputProject(for: project.selectedOutputLayout)
        let preset = ExportPerformancePreset(rawValue: environment["BLITZ_EXPORT_TEST_PRESET"] ?? "balanced") ?? .balanced
        let format: OutputVideoFormat = output.pathExtension == "mov" ? .mov : .mp4
        var baseSettings = RecordingSettings()
        baseSettings.outputDirectory = output.deletingLastPathComponent()
        let settings = store.recordingSettings(from: outputProject, baseSettings: baseSettings, outputFormat: format)
        let profile = ExportPerformanceProfile.resolved(
            preset: preset, sourceResolution: settings.outputResolution,
            sourceFramesPerSecond: settings.framesPerSecond, customResolution: .p1080,
            customFramesPerSecond: settings.framesPerSecond, customVideoQuality: .high)
        let take = store.recordingTake(from: outputProject, settings: settings, outputFormat: format)
        let hidden = ProjectExportRenderPlan.hiddenCaptureSources(Set(project.editorState.hiddenVideoSources.compactMap(SceneLayerKind.init(rawValue:))))
        let renderSettings = ProjectExportRenderPlan.settings(exportSettings: settings, profile: profile,
            outputLayout: outputProject.selectedOutputLayout, mutedAudioSources: Set(project.editorState.mutedAudioSources.compactMap(CaptureSource.init(rawValue:))),
            hiddenCaptureSources: hidden)
        let scenes = ProjectExportRenderPlan.sceneEvents(store.sceneEvents(from: outputProject),
                                                        hiddenCaptureSources: hidden, profile: profile)
        let result = try await Merger.exportFinalVideo(.init(
            take: take, settings: renderSettings, sceneEvents: scenes, backgroundMusic: nil,
            destinationURL: output, progressHandler: nil, timelineEdits: outputProject.edits, playbackRate: 1.3))
        let asset = AVURLAsset(url: result)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first)
        let size = try await video.load(.naturalSize)
        let rate = try await video.load(.nominalFrameRate)
        let sourceDuration = try await AVURLAsset(url: take.screenURL).load(.duration)
        let expected = TimelineTimeMap(takeDuration: sourceDuration, cuts: outputProject.edits.cuts, playbackRate: 1.3)
        XCTAssertEqual(duration.seconds, expected.outputDuration.seconds, accuracy: 0.1)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
        XCTAssertEqual(Double(rate), Double(profile.framesPerSecond), accuracy: 0.1)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty)
        print("REAL_EXPORT output=\(result.path) duration=\(duration.seconds) fps=\(rate) size=\(size)")
    }
}
