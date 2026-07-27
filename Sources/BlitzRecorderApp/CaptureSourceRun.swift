import Foundation
import CoreMedia
import ScreenCaptureKit

protocol ScreenCaptureRecording: AnyObject {
    var activeScreenCaptureStream: SCStream? { get }
    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws
    func update(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

extension ScreenCaptureRecording {
    var activeScreenCaptureStream: SCStream? { nil }
}

protocol CameraCaptureRecording: AnyObject {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

@MainActor
protocol RemoteCameraCaptureRecording: AnyObject {
    func startRemoteCamera(take: RecordingTake, settings: RecordingSettings, hostTimelineStartTime: UInt64) async throws
    func pauseRemoteCamera()
    func resumeRemoteCamera()
    func stopRemoteCamera(take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion
}

protocol MicrophoneCaptureRecording: AnyObject {
    var recordingTimelineOffset: CMTime { get }
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

protocol SystemAudioCaptureRecording: AnyObject {
    var recordingTimelineOffset: CMTime { get }
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func start(_ request: SystemAudioCaptureStartRequest) async throws
    func update(filter pickedScreenFilter: SCContentFilter?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

struct SystemAudioCaptureStartRequest {
    let url: URL
    let settings: RecordingSettings
    let pickedScreenFilter: SCContentFilter?
    let timelineStartTime: CMTime?
}

extension MicrophoneCaptureRecording {
    var recordingTimelineOffset: CMTime { .zero }
}

extension SystemAudioCaptureRecording {
    var recordingTimelineOffset: CMTime { .zero }

    func start(_ request: SystemAudioCaptureStartRequest) async throws {
        try await start(
            url: request.url,
            settings: request.settings,
            timelineStartTime: request.timelineStartTime
        )
    }

    func update(filter pickedScreenFilter: SCContentFilter?) async throws {}
}

struct CaptureSourceRunSummary {
    let completions: [CaptureSource: MediaWriterCompletion]
    let stopFailures: [CaptureSource: String]
    let timelineTrimOffset: CMTime
    let sourceTimelineOffsets: [CaptureSource: CMTime]

    init(
        completions: [CaptureSource: MediaWriterCompletion],
        stopFailures: [CaptureSource: String] = [:],
        timelineTrimOffset: CMTime = .zero,
        sourceTimelineOffsets: [CaptureSource: CMTime] = [:]
    ) {
        self.completions = completions
        self.stopFailures = stopFailures
        self.timelineTrimOffset = timelineTrimOffset
        self.sourceTimelineOffsets = sourceTimelineOffsets
    }

    var hasVideoMedia: Bool {
        completions[.screen]?.wroteMedia == true || completions[.camera]?.wroteMedia == true
    }

    var stopFailureWarning: String? {
        stopFailureWarning(for: Set(CaptureSource.allCases))
    }

    var savedRecordingStopWarning: String? {
        if let videoWarning = stopFailureWarning(for: [.screen, .camera]) {
            return videoWarning
        }

        let failedAudioSources = [CaptureSource.microphone, .systemAudio].filter {
            stopFailures[$0] != nil && completions[$0]?.wroteMedia != true
        }
        guard !failedAudioSources.isEmpty else { return nil }
        let names = failedAudioSources.map(\.rawValue).joined(separator: " and ")
        return "\(names) audio could not be finalized. Saved video is intact, but that audio track may be missing."
    }

    private func stopFailureWarning(for sources: Set<CaptureSource>) -> String? {
        let failures = CaptureSource.allCases.compactMap { source -> String? in
            guard sources.contains(source) else { return nil }
            guard let reason = stopFailures[source] else { return nil }
            return "\(source.rawValue): \(Self.userFacingStopFailureReason(for: source, reason: reason))"
        }
        guard !failures.isEmpty else { return nil }
        return "Some sources stopped with errors: \(failures.joined(separator: "; "))"
    }

    private static func userFacingStopFailureReason(for source: CaptureSource, reason: String) -> String {
        let lowercased = reason.lowercased()
        if source == .camera,
           lowercased.contains("remote iphone"),
           lowercased.contains("no video frames captured") {
            return "iPhone camera did not save usable video. Keep BlitzRecorder Camera open until recording stops, then retry."
        }
        if lowercased.contains("no video frames captured") {
            return "No video was captured from this source."
        }
        if lowercased.contains("cannot open") || lowercased.contains("operation not permitted") {
            return "BlitzRecorder could not open the saved media. Check recording-folder permission, then retry."
        }
        return reason
    }
}

struct CaptureSourceStopFailure: Error {
    let completion: MediaWriterCompletion
    let underlyingError: Error
}

struct CaptureSourceRetargetFailure: Error {
    let rollbackFailed: Bool
    let underlyingError: Error
}

struct CaptureSourceRunStartResult: Equatable {
    let hostTimelineStartTime: UInt64
    let timelineStartTime: CMTime

    static func == (lhs: CaptureSourceRunStartResult, rhs: CaptureSourceRunStartResult) -> Bool {
        lhs.hostTimelineStartTime == rhs.hostTimelineStartTime
            && CMTimeCompare(lhs.timelineStartTime, rhs.timelineStartTime) == 0
    }
}

@MainActor
final class CaptureSourceRun {
    let take: RecordingTake

    private var settings: RecordingSettings
    private var pickedScreenFilter: SCContentFilter?
    private var committedScreenCaptureSettings: RecordingSettings
    private var committedScreenCaptureFilter: SCContentFilter?
    private let screenRecorder: ScreenCaptureRecording
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
            if offset.isValid, offset.seconds.isFinite, CMTimeCompare(offset, .zero) > 0 {
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
            if offset.isValid, offset.seconds.isFinite, CMTimeCompare(offset, .zero) > 0 {
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

        for source in sourcesToStop {
            guard let adapter = sourceAdapters[source] else { continue }
            activeSources.remove(source)
            do {
                completions[source] = try await adapter.stop(settings)
            } catch let stopFailure as CaptureSourceStopFailure {
                completions[source] = stopFailure.completion
                stopFailures[source] = Self.sourceStopFailureDescription(stopFailure.underlyingError)
            } catch {
                stopFailures[source] = Self.sourceStopFailureDescription(error)
            }
        }
        return CaptureSourceRunSummary(
            completions: completions,
            stopFailures: stopFailures,
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
                timelineOffset: { .zero }
            ),
            .camera: cameraAdapter,
            .microphone: CaptureSourceRunAdapter(
                start: { settings, _, timeline in
                    try await audioRecorder.start(
                        url: take.audioURL,
                        settings: settings,
                        timelineStartTime: timeline.timelineStartTime
                    )
                },
                update: { _, _ in },
                pause: { audioRecorder.pause() },
                resume: { audioRecorder.resume() },
                stop: { _ in try await audioRecorder.stop() },
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
                timelineOffset: { systemAudioRecorder.recordingTimelineOffset }
            )
        ]
        return adapters
    }

    static func sourceStopFailureDescription(_ error: Error) -> String {
        if error is RecorderError {
            return error.localizedDescription
        }
        return error.recorderFailureDescription
    }
}

extension ScreenRecorder: ScreenCaptureRecording {}
extension CameraRecorder: CameraCaptureRecording {}
extension AudioRecorder: MicrophoneCaptureRecording {}
extension SystemAudioRecorder: SystemAudioCaptureRecording {}
