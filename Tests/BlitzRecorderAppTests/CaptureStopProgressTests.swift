import CoreMedia
import ScreenCaptureKit
import XCTest
@testable import BlitzRecorderApp

final class CaptureStopProgressTests: XCTestCase {
    func testSynchronizationReportsActualProgress() {
        let progress = CaptureStopProgress(phase: .synchronizingAudio, completed: 4,
            total: 4, pendingSources: [], synchronizationProgress: 0.42)
        XCTAssertEqual(progress.fraction, 0.42)
        XCTAssertEqual(progress.label, "42%")
    }

    @MainActor
    func testStopsAllSourcesBeforeWaitingAndSynchronizesAfterAllStops() async throws {
        let started = expectation(description: "All four sources began closing")
        started.expectedFulfillmentCount = 4
        let gate = CaptureStopGate(onStarted: { started.fulfill() })
        var settings = RecordingSettings()
        settings.enabledSources = Set(CaptureSource.allCases)
        settings.outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        settings.projectLibrary = .init(url: settings.outputDirectory, bookmarkData: nil)
        defer { try? FileManager.default.removeItem(at: settings.outputDirectory) }
        let take = try TakeFileStore().createTake(settings: settings)
        let run = CaptureSourceRun(
            take: take, settings: settings, pickedScreenFilter: nil,
            screenRecorder: ConcurrentStopRecorder(.init(source: .screen, gate: gate)),
            cameraRecorder: ConcurrentStopRecorder(.init(source: .camera, gate: gate)),
            audioRecorder: ConcurrentStopRecorder(.init(source: .microphone, gate: gate)),
            systemAudioRecorder: ConcurrentStopRecorder(.init(source: .systemAudio, gate: gate))
        )
        var updates: [CaptureStopProgress] = []
        run.onStopProgress = { updates.append($0) }
        try await run.start()
        let stopTask = Task { await run.stop() }
        await fulfillment(of: [started], timeout: 2)
        await gate.release()
        let result = await stopTask.value
        let synchronizedAfter = await gate.synchronizedAfter

        XCTAssertEqual(result.completions.count, 3)
        XCTAssertNotNil(result.stopFailures[.systemAudio])
        XCTAssertEqual(synchronizedAfter, Set(CaptureSource.allCases))
        XCTAssertEqual(updates.filter { $0.phase == .closingTracks }.map(\.completed), [0, 1, 2, 3, 4])
        XCTAssertEqual(updates.last?.phase, .synchronizingAudio)
        XCTAssertNil(updates.last?.fraction)
        XCTAssertEqual(updates.first?.fraction, 0)
        XCTAssertTrue(updates.dropLast().last?.pendingSources.isEmpty == true)
    }
}

private actor CaptureStopGate {
    let onStarted: @Sendable () -> Void
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private var finished: Set<CaptureSource> = []
    private(set) var synchronizedAfter: Set<CaptureSource> = []

    init(onStarted: @escaping @Sendable () -> Void) { self.onStarted = onStarted }

    func wait(_ source: CaptureSource) async {
        onStarted()
        if !isReleased {
            await withCheckedContinuation { continuations.append($0) }
        }
        finished.insert(source)
    }

    func release() {
        isReleased = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    func synchronize() { synchronizedAfter = finished }
}

private final class ConcurrentStopRecorder: ScreenCaptureRecording, CameraCaptureRecording,
    MicrophoneCaptureRecording, SystemAudioCaptureRecording {
    struct Configuration {
        let source: CaptureSource
        let gate: CaptureStopGate
    }
    let configuration: Configuration
    var recordingTimelineOffset: CMTime { .zero }

    init(_ configuration: Configuration) { self.configuration = configuration }

    func start(url: URL, settings: RecordingSettings, filter: SCContentFilter?, timelineStartTime: CMTime?) async throws {}
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {}
    func update(settings: RecordingSettings, filter: SCContentFilter?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion {
        await configuration.gate.wait(configuration.source)
        if configuration.source == .systemAudio { throw RecorderError.speechUnavailable }
        return .empty()
    }
    func finalizeSynchronization() async throws { await configuration.gate.synchronize() }
}
