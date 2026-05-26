import Foundation
import CoreMedia
import ScreenCaptureKit

protocol ScreenCaptureRecording: AnyObject {
    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

protocol CameraCaptureRecording: AnyObject {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

protocol MicrophoneCaptureRecording: AnyObject {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

protocol SystemAudioCaptureRecording: AnyObject {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
}

struct CaptureSourceRunSummary {
    let completions: [CaptureSource: MediaWriterCompletion]
    let stopFailures: [CaptureSource: String]

    init(
        completions: [CaptureSource: MediaWriterCompletion],
        stopFailures: [CaptureSource: String] = [:]
    ) {
        self.completions = completions
        self.stopFailures = stopFailures
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

        let failedAudioSources = [CaptureSource.microphone, .systemAudio].filter { stopFailures[$0] != nil }
        guard !failedAudioSources.isEmpty else { return nil }
        let names = failedAudioSources.map(\.rawValue).joined(separator: " and ")
        return "\(names) audio could not be finalized. Saved video is intact, but that audio track may be missing."
    }

    private func stopFailureWarning(for sources: Set<CaptureSource>) -> String? {
        let failures = CaptureSource.allCases.compactMap { source -> String? in
            guard sources.contains(source) else { return nil }
            guard let reason = stopFailures[source] else { return nil }
            return "\(source.rawValue): \(reason)"
        }
        guard !failures.isEmpty else { return nil }
        return "Some sources stopped with errors: \(failures.joined(separator: "; "))"
    }
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
    private var timelineStartTime: CMTime?
    private var hostTimelineStartTime: UInt64?
    private let sourceOrder: [CaptureSource] = [.screen, .camera, .microphone, .systemAudio]
    private let sourceAdapters: [CaptureSource: CaptureSourceRunAdapter]
    private var activeSources: Set<CaptureSource> = []
    private var isPaused = false

    private struct CaptureSourceRunAdapter {
        let start: (RecordingSettings, SCContentFilter?, CMTime?) async throws -> Void
        let pause: () -> Void
        let resume: () -> Void
        let stop: () async throws -> MediaWriterCompletion
    }

    init(
        take: RecordingTake,
        settings: RecordingSettings,
        pickedScreenFilter: SCContentFilter?,
        timelineStartTime: CMTime? = nil,
        screenRecorder: ScreenCaptureRecording,
        cameraRecorder: CameraCaptureRecording,
        audioRecorder: MicrophoneCaptureRecording,
        systemAudioRecorder: SystemAudioCaptureRecording
    ) {
        self.take = take
        self.settings = settings
        self.pickedScreenFilter = pickedScreenFilter
        self.timelineStartTime = timelineStartTime
        self.sourceAdapters = Self.makeSourceAdapters(
            take: take,
            screenRecorder: screenRecorder,
            cameraRecorder: cameraRecorder,
            audioRecorder: audioRecorder,
            systemAudioRecorder: systemAudioRecorder
        )
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
        let timelineStartTime = establishTimelineStartIfNeeded().timelineStartTime

        for source in sourceOrder where settings.enabledSources.contains(source) && !activeSources.contains(source) {
            guard let adapter = sourceAdapters[source] else { continue }
            activeSources.insert(source)
            do {
                try await adapter.start(settings, pickedScreenFilter, timelineStartTime)
            } catch {
                _ = try? await adapter.stop()
                activeSources.remove(source)
                throw error
            }
            if isPaused {
                adapter.pause()
            }
        }
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
        var completions: [CaptureSource: MediaWriterCompletion] = [:]
        var stopFailures: [CaptureSource: String] = [:]
        let sourcesToStop = sourceOrder.filter { activeSources.contains($0) }
        activeSources.removeAll()

        for source in sourcesToStop {
            guard let adapter = sourceAdapters[source] else { continue }
            do {
                completions[source] = try await adapter.stop()
            } catch {
                stopFailures[source] = sourceStopFailureDescription(error)
            }
        }
        return CaptureSourceRunSummary(completions: completions, stopFailures: stopFailures)
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
        audioRecorder: MicrophoneCaptureRecording,
        systemAudioRecorder: SystemAudioCaptureRecording
    ) -> [CaptureSource: CaptureSourceRunAdapter] {
        [
            .screen: CaptureSourceRunAdapter(
                start: { settings, pickedScreenFilter, timelineStartTime in
                    try await screenRecorder.start(
                        url: take.screenURL,
                        settings: settings,
                        filter: pickedScreenFilter,
                        timelineStartTime: timelineStartTime
                    )
                },
                pause: { screenRecorder.pause() },
                resume: { screenRecorder.resume() },
                stop: { try await screenRecorder.stop() }
            ),
            .camera: CaptureSourceRunAdapter(
                start: { settings, _, timelineStartTime in
                    try await cameraRecorder.start(
                        url: take.cameraURL,
                        settings: settings,
                        timelineStartTime: timelineStartTime
                    )
                },
                pause: { cameraRecorder.pause() },
                resume: { cameraRecorder.resume() },
                stop: { try await cameraRecorder.stop() }
            ),
            .microphone: CaptureSourceRunAdapter(
                start: { settings, _, timelineStartTime in
                    try audioRecorder.start(
                        url: take.audioURL,
                        settings: settings,
                        timelineStartTime: timelineStartTime
                    )
                },
                pause: { audioRecorder.pause() },
                resume: { audioRecorder.resume() },
                stop: { try await audioRecorder.stop() }
            ),
            .systemAudio: CaptureSourceRunAdapter(
                start: { settings, _, timelineStartTime in
                    try await systemAudioRecorder.start(
                        url: take.systemAudioURL,
                        settings: settings,
                        timelineStartTime: timelineStartTime
                    )
                },
                pause: { systemAudioRecorder.pause() },
                resume: { systemAudioRecorder.resume() },
                stop: { try await systemAudioRecorder.stop() }
            )
        ]
    }

    private func sourceStopFailureDescription(_ error: Error) -> String {
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
