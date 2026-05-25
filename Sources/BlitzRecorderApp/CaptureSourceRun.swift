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
        let failures = CaptureSource.allCases.compactMap { source -> String? in
            guard let reason = stopFailures[source] else { return nil }
            return "\(source.rawValue): \(reason)"
        }
        guard !failures.isEmpty else { return nil }
        return "Some sources stopped with errors: \(failures.joined(separator: "; "))"
    }
}

@MainActor
final class CaptureSourceRun {
    let take: RecordingTake

    private let settings: RecordingSettings
    private let pickedScreenFilter: SCContentFilter?
    private let timelineStartTime: CMTime?
    private let screenRecorder: ScreenCaptureRecording
    private let cameraRecorder: CameraCaptureRecording
    private let audioRecorder: MicrophoneCaptureRecording
    private let systemAudioRecorder: SystemAudioCaptureRecording
    private var activeSources: Set<CaptureSource> = []

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
        self.screenRecorder = screenRecorder
        self.cameraRecorder = cameraRecorder
        self.audioRecorder = audioRecorder
        self.systemAudioRecorder = systemAudioRecorder
    }

    func start() async throws {
        do {
            if settings.enabledSources.contains(.screen) {
                activeSources.insert(.screen)
                try await screenRecorder.start(
                    url: take.screenURL,
                    settings: settings,
                    filter: pickedScreenFilter,
                    timelineStartTime: timelineStartTime
                )
            }
            if settings.enabledSources.contains(.camera) {
                activeSources.insert(.camera)
                try await cameraRecorder.start(url: take.cameraURL, settings: settings, timelineStartTime: timelineStartTime)
            }
            if settings.enabledSources.contains(.microphone) {
                activeSources.insert(.microphone)
                try audioRecorder.start(url: take.audioURL, settings: settings, timelineStartTime: timelineStartTime)
            }
            if settings.enabledSources.contains(.systemAudio) {
                activeSources.insert(.systemAudio)
                try await systemAudioRecorder.start(
                    url: take.systemAudioURL,
                    settings: settings,
                    timelineStartTime: timelineStartTime
                )
            }
        } catch {
            _ = await stop()
            throw error
        }
    }

    func pause() {
        if activeSources.contains(.screen) {
            screenRecorder.pause()
        }
        if activeSources.contains(.camera) {
            cameraRecorder.pause()
        }
        if activeSources.contains(.microphone) {
            audioRecorder.pause()
        }
        if activeSources.contains(.systemAudio) {
            systemAudioRecorder.pause()
        }
    }

    func resume() {
        if activeSources.contains(.screen) {
            screenRecorder.resume()
        }
        if activeSources.contains(.camera) {
            cameraRecorder.resume()
        }
        if activeSources.contains(.microphone) {
            audioRecorder.resume()
        }
        if activeSources.contains(.systemAudio) {
            systemAudioRecorder.resume()
        }
    }

    func stop() async -> CaptureSourceRunSummary {
        var completions: [CaptureSource: MediaWriterCompletion] = [:]
        var stopFailures: [CaptureSource: String] = [:]
        let sourcesToStop = activeSources
        activeSources.removeAll()

        if sourcesToStop.contains(.screen) {
            do {
                completions[.screen] = try await screenRecorder.stop()
            } catch {
                stopFailures[.screen] = error.localizedDescription
            }
        }
        if sourcesToStop.contains(.camera) {
            do {
                completions[.camera] = try await cameraRecorder.stop()
            } catch {
                stopFailures[.camera] = error.localizedDescription
            }
        }
        if sourcesToStop.contains(.microphone) {
            do {
                completions[.microphone] = try await audioRecorder.stop()
            } catch {
                stopFailures[.microphone] = error.localizedDescription
            }
        }
        if sourcesToStop.contains(.systemAudio) {
            do {
                completions[.systemAudio] = try await systemAudioRecorder.stop()
            } catch {
                stopFailures[.systemAudio] = error.localizedDescription
            }
        }
        return CaptureSourceRunSummary(completions: completions, stopFailures: stopFailures)
    }
}

extension ScreenRecorder: ScreenCaptureRecording {}
extension CameraRecorder: CameraCaptureRecording {}
extension AudioRecorder: MicrophoneCaptureRecording {}
extension SystemAudioRecorder: SystemAudioCaptureRecording {}
