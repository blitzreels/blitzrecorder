import AVFoundation
import SwiftUI
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

extension ProjectExportRegressionTests {
    @MainActor
    func testExportKeepsMainActorAvailableAndPreservesAnInFlightRename() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let suite = "ExportNavigation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingSettingsStore.save(fixture.settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        var progressCount = 0
        var renamed = false
        var callbackError: Error?
        coordinator.onExportProgress = { progress in
            progressCount += 1
            guard progressCount >= 2, progress < 1, !renamed else { return }
            do {
                _ = try TakeFileStore().renameProject(.init(projectURL: fixture.take.projectURL,
                    title: "Renamed during export", settings: fixture.settings))
                renamed = true
            } catch { callbackError = error }
        }
        var tickCount = 0
        var longestGap: TimeInterval = 0
        let ticker = Task { @MainActor in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                let now = ProcessInfo.processInfo.systemUptime
                longestGap = max(longestGap, now - previous)
                previous = now
                tickCount += 1
            }
        }
        defer { ticker.cancel() }
        let output = fixture.root.appendingPathComponent("test-export.mp4")
        let result = try await coordinator.exportProjectForAgent(.init(
            projectURL: fixture.take.projectURL, outputFormat: .mp4,
            performanceProfile: .resolved(preset: .custom, sourceResolution: .p720, sourceFramesPerSecond: 30,
                customResolution: .p720, customFramesPerSecond: 30, customVideoQuality: .web),
            destinationURL: output, hiddenVideoSources: [], mutedAudioSources: [], backgroundMusic: nil))
        XCTAssertNil(callbackError)
        XCTAssertTrue(renamed)
        XCTAssertGreaterThan(progressCount, 2)
        XCTAssertGreaterThan(tickCount, 2)
        XCTAssertLessThan(longestGap, 1, "Export must leave the main actor available for navigation")
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(coordinator.isExporting)
        XCTAssertEqual(result.url, output)
        let saved = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
        XCTAssertEqual(saved.title, "Renamed during export")
        XCTAssertEqual(saved.exports.last?.path, output.path)
        let media = try await SyntheticRecording.inspectVideo(output)
        XCTAssertGreaterThan(media.duration, 2.9)
        print("EXPORT_NAVIGATION ticks=\(tickCount) max_gap_ms=\(longestGap * 1000)")
    }
}


extension ProjectExportRegressionTests {
    @MainActor
    func testLibraryNavigationDuringRealExport() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let historyPath = environment["BLITZ_LIBRARY_PERF_HISTORY"],
              let projectPath = environment["BLITZ_LIBRARY_PERF_PROJECT"] else {
            throw XCTSkip("Provide a project history and source project for the read-only library performance check.")
        }
        let fixture = try SyntheticRecording()
        let store = TakeFileStore()
        let project = try store.loadRecordingProject(at: URL(fileURLWithPath: projectPath))
        let projectData = try Data(contentsOf: URL(fileURLWithPath: projectPath))
        let historyData = try Data(contentsOf: URL(fileURLWithPath: historyPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let history = try decoder.decode(RecordingProjectHistory.self, from: historyData)
        try historyData.write(to: store.projectHistoryURL(for: fixture.settings))
        let suite = "LibraryExportPerformance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingSettingsStore.save(fixture.settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let automaticPreference = UserDefaults.standard.object(forKey: "transcription.automatic.enabled")
        vm.transcriptionController.isAutomaticEnabled = false
        defer {
            UserDefaults.standard.set(automaticPreference, forKey: "transcription.automatic.enabled")
            vm.prepareForWindowClose()
        }
        vm.applyExportProject(URL(fileURLWithPath: projectPath))
        vm.showProjects()
        let host = NSHostingView(rootView: ProjectLibraryView(vm: vm)
            .environmentObject(AppUpdateController()).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 1440, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }

        let outputProject = project.outputProject(for: project.selectedOutputLayout)
        var baseSettings = fixture.settings
        baseSettings.outputResolution = .p1080
        let settings = store.recordingSettings(from: outputProject, baseSettings: baseSettings, outputFormat: .mp4)
        let profile = ExportPerformanceProfile.resolved(preset: .balanced,
            sourceResolution: settings.outputResolution, sourceFramesPerSecond: settings.framesPerSecond,
            customResolution: .p1080, customFramesPerSecond: settings.framesPerSecond, customVideoQuality: .high)
        let take = store.recordingTake(from: outputProject, settings: settings, outputFormat: .mp4)
        let renderSettings = ProjectExportRenderPlan.settings(exportSettings: settings, profile: profile,
            outputLayout: outputProject.selectedOutputLayout, mutedAudioSources: [], hiddenCaptureSources: [])
        let scenes = ProjectExportRenderPlan.sceneEvents(store.sceneEvents(from: outputProject),
            hiddenCaptureSources: [], profile: profile)
        let destination = fixture.root.appendingPathComponent("library-performance.mp4")
        var finished = false
        var progressCount = 0
        let export = Task {
            defer { finished = true }
            return try await Merger.exportFinalVideo(.init(take: take, settings: renderSettings,
                sceneEvents: scenes, backgroundMusic: nil, destinationURL: destination,
                progressHandler: { value in vm.exportProgress = value; progressCount += 1 },
                timelineEdits: outputProject.edits))
        }
        defer { export.cancel() }
        var intervals: [Double] = []
        var stalls: [String] = []
        var navigations = 0
        var previous = ProcessInfo.processInfo.systemUptime
        let started = previous
        while !finished {
            try await Task.sleep(for: .milliseconds(20))
            let now = ProcessInfo.processInfo.systemUptime
            let interval = now - previous
            intervals.append(interval)
            if interval > 0.1 {
                stalls.append("at_s=\(now - started) gap_ms=\(interval * 1000) navigation=\(navigations) section=\(vm.projectLibraryNavigation.section.rawValue)")
            }
            previous = now
            if intervals.count.isMultiple(of: 12) {
                vm.projectLibraryNavigation.section = navigations.isMultiple(of: 2) ? .recordings : .shared
                if !history.entries.isEmpty {
                    vm.projectLibraryNavigation.selectedProjectIDs = [history.entries[navigations % history.entries.count].id]
                }
                vm.showProjects()
                host.layoutSubtreeIfNeeded()
                navigations += 1
            }
        }
        let output = try await export.value
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        let sorted = intervals.sorted()
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let maximum = sorted.last ?? 0
        XCTAssertGreaterThan(navigations, 5)
        XCTAssertGreaterThan(duration, 1)
        XCTAssertLessThan(p95, 0.1)
        XCTAssertLessThan(maximum, 0.5)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: historyPath)), historyData)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: projectPath)), projectData)
        XCTAssertFalse(ProjectLibraryMetadataStore.shared.metadata.isEmpty)
        print("LIBRARY_EXPORT_STALLS \(stalls.joined(separator: "; "))")
        print("LIBRARY_EXPORT projects=\(history.entries.count) navigations=\(navigations) elapsed_s=\(ProcessInfo.processInfo.systemUptime - started) p95_ms=\(p95 * 1000) max_gap_ms=\(maximum * 1000) progress_updates=\(progressCount) media_seconds=\(duration)")
    }
}
