import Foundation
import CoreMedia
import ScreenCaptureKit

@MainActor
final class CaptureSourceRun {
    let take: RecordingTake
    var onStopProgress: ((CaptureStopProgress) -> Void)?

    private var settings: RecordingSettings
    private var pickedScreenFilter: SCContentFilter?
    private var committedScreenCaptureSettings: RecordingSettings
    private var committedScreenCaptureFilter: SCContentFilter?
    private let screenRecorder: ScreenCaptureRecording
    private let microphoneRecorder: MicrophoneCaptureRecording
    private var timelineStartTime: CMTime?
    private var hostTimelineStartTime: UInt64?
    private var timelineTrimOffset = CMTime.zero
    private var sourceTimelineOffsets: [CaptureSource: CMTime] = [:]
    private let sourceOrder: [CaptureSource] = [.screen, .microphone, .systemAudio, .camera]
    private let stopOrder: [CaptureSource] = [.microphone, .systemAudio, .camera, .screen]
    private let sourceAdapters: [CaptureSource: CaptureSourceRunAdapter]
    private var activeSources: Set<CaptureSource> = []
    private var isPaused = false

    private struct CaptureSourceRunAdapter {
        let start: (RecordingSettings, SCContentFilter?, CaptureSourceRunStartResult) async throws -> Void
        let update: (RecordingSettings, SCContentFilter?) async throws -> Void
        let pause: () -> Void
        let resume: () -> Void
        let stop: (RecordingSettings) async throws -> MediaWriterCompletion
        let finalize: (AudioSynchronizationProgress) async throws -> Void
        let timelineOffset: () -> CMTime
    }

    init(
        take: RecordingTake,
        settings: RecordingSettings,
        pickedScreenFilter: SCContentFilter?,
        timelineStartTime: CMTime? = nil,
        screenRecorder: ScreenCaptureRecording,
        cameraRecorder: CameraCaptureRecording,
        remoteCameraRecorder: RemoteCameraCaptureRecording? = nil,
        audioRecorder: MicrophoneCaptureRecording,
        systemAudioRecorder: SystemAudioCaptureRecording
    ) {
        self.take = take
        self.settings = settings
        self.pickedScreenFilter = pickedScreenFilter
        committedScreenCaptureSettings = settings
        committedScreenCaptureFilter = pickedScreenFilter
        self.screenRecorder = screenRecorder
        microphoneRecorder = audioRecorder
        self.timelineStartTime = timelineStartTime
        self.sourceAdapters = Self.makeSourceAdapters(
            take: take,
            screenRecorder: screenRecorder,
            cameraRecorder: cameraRecorder,
            remoteCameraRecorder: remoteCameraRecorder,
            audioRecorder: audioRecorder,
            systemAudioRecorder: systemAudioRecorder
        )
    }

    var activeScreenCaptureStream: SCStream? {
        guard activeSources.contains(.screen) else { return nil }
        return screenRecorder.activeScreenCaptureStream
    }

    @discardableResult
    func start(
        prerollSeconds: Int = 0,
        prerollHandler: ((Int) -> Void)? = nil
    ) async throws -> CaptureSourceRunStartResult {
        do {
            try await runPreroll(seconds: prerollSeconds, handler: prerollHandler)
            let timeline = establishTimelineStartIfNeeded()
            try await startEnabledSources(settings: settings, pickedScreenFilter: pickedScreenFilter)
            let contentStartTime = CMClockGetTime(CMClockGetHostTimeClock())
            let offset = CMTimeSubtract(contentStartTime, timeline.timelineStartTime)
            if Self.isPositive(offset) {
                timelineTrimOffset = CMTimeConvertScale(
                    offset,
                    timescale: 600,
                    method: .roundHalfAwayFromZero
                )
            }
            return timeline
        } catch {
            _ = await stop()
            throw error
        }
    }

    func startEnabledSources(
        settings: RecordingSettings,
        pickedScreenFilter: SCContentFilter?
    ) async throws {
        self.settings = settings
        self.pickedScreenFilter = pickedScreenFilter
        let timeline = establishTimelineStartIfNeeded()

        let sourcesToStart = sourceOrder.filter {
            settings.enabledSources.contains($0) && !activeSources.contains($0)
        }
        guard !sourcesToStart.isEmpty else { return }

        var startupTasks: [(source: CaptureSource, task: Task<Void, Error>)] = []
        for source in sourcesToStart {
            guard let adapter = sourceAdapters[source] else { continue }
            activeSources.insert(source)

            let task = Task { @MainActor in
                try await adapter.start(settings, pickedScreenFilter, timeline)
            }
            startupTasks.append((source, task))
        }

        do {
            for startupTask in startupTasks {
                try await startupTask.task.value
            }
        } catch {
            for startupTask in startupTasks {
                startupTask.task.cancel()
            }
            _ = await stopSources(sourcesToStart, settings: settings)
            throw error
        }

        for source in sourcesToStart {
            guard let adapter = sourceAdapters[source] else { continue }
            let offset = adapter.timelineOffset()
            if Self.isPositive(offset) {
                sourceTimelineOffsets[source] = offset
            }
        }

        for source in sourcesToStart {
            guard activeSources.contains(source),
                  let adapter = sourceAdapters[source] else { continue }
            if isPaused {
                adapter.pause()
            }
        }

        if sourcesToStart.contains(.screen) || sourcesToStart.contains(.systemAudio) {
            committedScreenCaptureSettings = settings
            committedScreenCaptureFilter = pickedScreenFilter
        }
    }

    func updateScreenCapture(
        settings: RecordingSettings,
        pickedScreenFilter: SCContentFilter?
    ) async throws {
        let previousSettings = committedScreenCaptureSettings
        let previousFilter = committedScreenCaptureFilter
        var attemptedSources: [CaptureSource] = []
        var firstError: Error?
        for source in [CaptureSource.screen, .systemAudio] {
            guard activeSources.contains(source),
                  settings.enabledSources.contains(source),
                  let adapter = sourceAdapters[source] else {
                continue
            }
            attemptedSources.append(source)
            do {
                try await adapter.update(settings, pickedScreenFilter)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            var rollbackFailed = false
            for source in attemptedSources.reversed() {
                guard let adapter = sourceAdapters[source] else { continue }
                do {
                    try await adapter.update(previousSettings, previousFilter)
                } catch {
                    rollbackFailed = true
                }
            }
            throw CaptureSourceRetargetFailure(
                rollbackFailed: rollbackFailed,
                underlyingError: firstError
            )
        }
        self.settings = settings
        self.pickedScreenFilter = pickedScreenFilter
        committedScreenCaptureSettings = settings
        committedScreenCaptureFilter = pickedScreenFilter
    }

    func switchMicrophone(to deviceID: String) async throws {
        guard activeSources.contains(.microphone) else {
            throw RecorderError.microphoneUnavailable
        }
        try await microphoneRecorder.switchMicrophone(to: deviceID)
    }

    func pause() {
        isPaused = true
        for source in sourceOrder where activeSources.contains(source) {
            sourceAdapters[source]?.pause()
        }
    }

    func resume() {
        isPaused = false
        for source in sourceOrder where activeSources.contains(source) {
            sourceAdapters[source]?.resume()
        }
    }

    func stop() async -> CaptureSourceRunSummary {
        let sourcesToStop = stopOrder.filter { activeSources.contains($0) }
        activeSources.removeAll()
        return await stopSources(sourcesToStop, settings: settings)
    }

    private func stopSources(_ sourcesToStop: [CaptureSource], settings: RecordingSettings) async -> CaptureSourceRunSummary {
        var completions: [CaptureSource: MediaWriterCompletion] = [:]
        var stopFailures: [CaptureSource: String] = [:]
        var synchronizationFailures: Set<CaptureSource> = []

        var pendingSources = sourcesToStop
        onStopProgress?(.init(phase: .closingTracks, completed: 0,
                              total: sourcesToStop.count, pendingSources: pendingSources))
        let startedAt = ContinuousClock.now
        let stops = sourcesToStop.compactMap { source -> Task<Void, Never>? in
            guard let adapter = sourceAdapters[source] else { return nil }
            activeSources.remove(source)
            return Task { @MainActor in
                let sourceStartedAt = ContinuousClock.now
                do {
                    completions[source] = try await adapter.stop(settings)
                } catch let stopFailure as CaptureSourceStopFailure {
                    completions[source] = stopFailure.completion
                    stopFailures[source] = Self.sourceStopFailureDescription(stopFailure.underlyingError)
                } catch {
                    stopFailures[source] = Self.sourceStopFailureDescription(error)
                }
                pendingSources.removeAll { $0 == source }
                self.onStopProgress?(.init(phase: .closingTracks,
                    completed: sourcesToStop.count - pendingSources.count,
                    total: sourcesToStop.count, pendingSources: pendingSources))
                NSLog("Capture stop %@: %@", source.rawValue, String(describing: sourceStartedAt.duration(to: .now)))
            }
        }
        for stop in stops { await stop.value }

        for source in sourcesToStop {
            guard let adapter = sourceAdapters[source] else { continue }
            if source == .microphone {
                onStopProgress?(.init(phase: .synchronizingAudio, completed: sourcesToStop.count,
                                      total: sourcesToStop.count, pendingSources: []))
            }
            do {
                try await adapter.finalize(.init(onProgress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.onStopProgress?(.init(phase: .synchronizingAudio,
                            completed: sourcesToStop.count, total: sourcesToStop.count, pendingSources: [],
                            synchronizationProgress: fraction))
                    }
                }))
            } catch {
                stopFailures[source] = Self.sourceStopFailureDescription(error)
                synchronizationFailures.insert(source)
            }
        }
        NSLog("Capture stop and synchronization: %@", String(describing: startedAt.duration(to: .now)))
        return CaptureSourceRunSummary(
            completions: completions,
            stopFailures: stopFailures,
            synchronizationFailures: synchronizationFailures,
            timelineTrimOffset: timelineTrimOffset,
            sourceTimelineOffsets: sourceTimelineOffsets
        )
    }

    private func runPreroll(seconds: Int, handler: ((Int) -> Void)?) async throws {
        guard seconds > 0 else { return }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            try Task.checkCancellation()
            handler?(remaining)
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func establishTimelineStartIfNeeded() -> CaptureSourceRunStartResult {
        if let hostTimelineStartTime, let timelineStartTime {
            return CaptureSourceRunStartResult(
                hostTimelineStartTime: hostTimelineStartTime,
                timelineStartTime: timelineStartTime
            )
        }

        let hostTime = DispatchTime.now().uptimeNanoseconds
        let timelineTime = timelineStartTime ?? CMClockGetTime(CMClockGetHostTimeClock())
        hostTimelineStartTime = hostTime
        timelineStartTime = timelineTime
        return CaptureSourceRunStartResult(
            hostTimelineStartTime: hostTime,
            timelineStartTime: timelineTime
        )
    }

    private static func makeSourceAdapters(
        take: RecordingTake,
        screenRecorder: ScreenCaptureRecording,
        cameraRecorder: CameraCaptureRecording,
        remoteCameraRecorder: RemoteCameraCaptureRecording?,
        audioRecorder: MicrophoneCaptureRecording,
        systemAudioRecorder: SystemAudioCaptureRecording
    ) -> [CaptureSource: CaptureSourceRunAdapter] {
        let cameraAdapter: CaptureSourceRunAdapter
        if let remoteCameraRecorder {
            cameraAdapter = CaptureSourceRunAdapter(
                start: { settings, _, timeline in
                    try await remoteCameraRecorder.startRemoteCamera(
                        take: take,
                        settings: settings,
                        hostTimelineStartTime: timeline.hostTimelineStartTime
                    )
                },
                update: { _, _ in },
                pause: { remoteCameraRecorder.pauseRemoteCamera() },
                resume: { remoteCameraRecorder.resumeRemoteCamera() },
                stop: { settings in
                    try await remoteCameraRecorder.stopRemoteCamera(take: take, settings: settings)
                },
                finalize: { _ in },
                timelineOffset: { .zero }
            )
        } else {
            cameraAdapter = CaptureSourceRunAdapter(
                start: { settings, _, timeline in
                    try await cameraRecorder.start(
                        url: take.cameraURL,
                        settings: settings,
                        timelineStartTime: timeline.timelineStartTime
                    )
                },
                update: { _, _ in },
                pause: { cameraRecorder.pause() },
                resume: { cameraRecorder.resume() },
                stop: { _ in try await cameraRecorder.stop() },
                finalize: { _ in },
                timelineOffset: { .zero }
            )
        }

        let adapters: [CaptureSource: CaptureSourceRunAdapter] = [
            .screen: CaptureSourceRunAdapter(
                start: { settings, pickedScreenFilter, timeline in
                    try await screenRecorder.start(
                        url: take.screenURL,
                        settings: settings,
                        filter: pickedScreenFilter,
                        timelineStartTime: timeline.timelineStartTime
                    )
                },
                update: { settings, pickedScreenFilter in
                    try await screenRecorder.update(settings: settings, filter: pickedScreenFilter)
                },
                pause: { screenRecorder.pause() },
                resume: { screenRecorder.resume() },
                stop: { _ in try await screenRecorder.stop() },
                finalize: { _ in },
                timelineOffset: { .zero }
            ),
            .camera: cameraAdapter,
            .microphone: CaptureSourceRunAdapter(
                start: { settings, _, timeline in
                    try await audioRecorder.start(
                        url: take.microphoneCaptureURL,
                        settings: settings,
                        timelineStartTime: timeline.timelineStartTime
                    )
                },
                update: { _, _ in },
                pause: { audioRecorder.pause() },
                resume: { audioRecorder.resume() },
                stop: { _ in try await audioRecorder.stop() },
                finalize: { try await audioRecorder.finalizeSynchronization($0) },
                timelineOffset: { audioRecorder.recordingTimelineOffset }
            ),
            .systemAudio: CaptureSourceRunAdapter(
                start: { settings, pickedScreenFilter, timeline in
                    try await systemAudioRecorder.start(SystemAudioCaptureStartRequest(
                        url: take.systemAudioURL,
                        settings: settings,
                        pickedScreenFilter: pickedScreenFilter,
                        timelineStartTime: timeline.timelineStartTime
                    ))
                },
                update: { _, pickedScreenFilter in
                    try await systemAudioRecorder.update(filter: pickedScreenFilter)
                },
                pause: { systemAudioRecorder.pause() },
                resume: { systemAudioRecorder.resume() },
                stop: { _ in try await systemAudioRecorder.stop() },
                finalize: { _ in },
                timelineOffset: { systemAudioRecorder.recordingTimelineOffset }
            )
        ]
        return adapters
    }

    private static func isPositive(_ offset: CMTime) -> Bool {
        offset.isValid && offset.seconds.isFinite && CMTimeCompare(offset, .zero) > 0
    }

    static func sourceStopFailureDescription(_ error: Error) -> String {
        if error is RecorderError {
            return error.localizedDescription
        }
        return error.recorderFailureDescription
    }
}
