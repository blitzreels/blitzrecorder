import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation
import Observation
import OSLog

private final class NotificationObserverBag: @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []

    deinit {
        removeAll()
    }

    func replace(_ observers: [NSObjectProtocol]) {
        lock.lock()
        let oldObservers = self.observers
        self.observers = observers
        lock.unlock()

        for observer in oldObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func removeAll() {
        lock.lock()
        let oldObservers = observers
        observers = []
        lock.unlock()

        for observer in oldObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

@Observable
@MainActor
final class CameraCaptureController {
    static let logger = Logger(
        subsystem: "dev.blitzreels.blitzrecorder.camera",
        category: "CameraCapture"
    )

    let session = AVCaptureSession()

    var isPreviewRunning = false
    var isRecording = false
    var statusMessage = "Camera is off"
    var capabilities: RemoteCameraCapabilities?
    var cinematicFocusCandidates: [CameraCinematicFocusCandidate] = []

    var activeDevice: AVCaptureDevice?
    var activeLens: RemoteCameraLens = .wide
    var activePrefersCinematicDevice = false
    let movieOutput = AVCaptureMovieFileOutput()
    let previewOutput = AVCaptureVideoDataOutput()
    let metadataOutput = AVCaptureMetadataOutput()
    let sessionQueue = DispatchQueue(label: "blitzrecorder.camera-capture-session", qos: .userInitiated)
    let previewQueue = DispatchQueue(label: "blitzrecorder.camera-monitor-preview")
    let metadataQueue = DispatchQueue(label: "blitzrecorder.camera-cinematic-metadata")
    let previewDelegate = CameraMonitorPreviewDelegate()
    let metadataDelegate = CinematicMetadataDelegate()
    let recordingLibrary = CameraRecordingLibrary()
    var activeVideoInput: AVCaptureDeviceInput?
    var activeAudioInput: AVCaptureDeviceInput?
    var recordingDelegate: MovieRecordingDelegate?
    var activeRecordingURL: URL?
    var captureSettingsAreLockedForRecording: Bool {
        isRecording || recordingDelegate != nil || activeRecordingURL != nil
    }
    var activeRecordingDiagnostics: RemoteCameraRecordingDiagnostics?
    var activeRecordingWarningAccumulator = RemoteCameraRecordingWarningAccumulator()
    var activeCaptureProfileID: RemoteCameraCaptureProfileID = .automatic
    var activeCaptureCodecLabel: String?
    var activeCaptureFormatLabel: String?
    var activeCinematicVideoEnabled = false
    var activeCinematicFocusMetadataEnabled = false
    var activeCinematicAperture: Double?
    var activeSettings = RemoteCameraSettings()
    var latestCinematicFocusCandidates: [CameraCinematicFocusCandidate] = []
    var lastFocusCandidatePublishTime = TimeInterval.zero
    var cinematicSceneObservation: NSKeyValueObservation?
    var cinematicSceneWarning: String?
    var cinematicFocusMetadataWarning: String?
    var systemPressureObservation: NSKeyValueObservation?
    var lensSmudgeObservation: NSKeyValueObservation?
    var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    var rotationObservation: NSKeyValueObservation?
    var onLevelRotationChanged: (@MainActor () -> Void)?
    var lensSmudgeWarning: String?
    var systemPressureWarning: String?
    var systemPressurePreviewLoadProfile = CameraMonitorPreviewLoadProfile.normal
    var networkPreviewLoadProfile = CameraMonitorPreviewLoadProfile.normal
    var captureSessionWarning: String?
    private let sessionNotificationObservers = NotificationObserverBag()
    var onMonitorFrame: (@Sendable (Data, Int, Int) -> Void)?
    var onMonitorVideoFrame: (@Sendable (RemoteCameraMonitorVideoFrame) -> Void)?
    var onMonitorFrameDropped: (@Sendable () -> Void)?
    var onRecordingFinishedUnexpectedly: (@Sendable (Result<CameraRecordingResult, Error>) -> Void)?
    var onCaptureWarningChanged: (@MainActor @Sendable (String?) -> Void)?

    var captureWarning: String? {
        var warnings: [String] = []
        func append(_ warning: String?) {
            guard let warning = warning?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !warning.isEmpty,
                  !warnings.contains(warning) else {
                return
            }
            warnings.append(warning)
        }
        if let captureSessionWarning {
            append(captureSessionWarning)
        }
        if let systemPressureWarning {
            append(systemPressureWarning)
        }
        append(lensSmudgeWarning)
        if activeCinematicVideoEnabled {
            append(cinematicSceneWarning)
            append(cinematicFocusMetadataWarning)
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: ". ")
    }

    init() {
        sessionNotificationObservers.replace(makeSessionNotificationObservers())
    }

    var capabilityBuilder: RemoteCameraCaptureCapabilityBuilder {
        RemoteCameraCaptureCapabilityBuilder(movieOutput: movieOutput)
    }

    private var settingsPlanner: CameraCaptureSettingsPlanner {
        CameraCaptureSettingsPlanner(capabilityBuilder: capabilityBuilder)
    }

    var captureProfileID: RemoteCameraCaptureProfileID {
        activeCaptureProfileID
    }

    var captureCodecLabel: String? {
        activeCaptureCodecLabel
    }

    var captureFormatLabel: String? {
        activeCaptureFormatLabel
    }

    func configure() async {
        guard await requestAccess(for: .video) else {
            statusMessage = "Allow camera access"
            return
        }
        await configureSession(lens: activeLens)
    }

    func stopSessionIfIdle() async {
        guard !isRecording else { return }
        let isRunning = await runOnSessionQueue { [session] in
            guard session.isRunning else { return false }
            session.stopRunning()
            return session.isRunning
        }
        isPreviewRunning = isRunning
        if !isRunning {
            statusMessage = "Camera paused"
        }
    }

    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func setLens(_ lens: RemoteCameraLens) async {
        guard capabilityBuilder.supportedLenses().contains(lens) else {
            statusMessage = "\(lens.displayName) not available"
            return
        }
        let didSuspendPreview = await suspendMonitorPreviewForSettingsChange()
        await configureSession(lens: lens)
        await setZoomFactor(1)
        await resumeMonitorPreviewAfterSettingsChange(if: didSuspendPreview)
    }

    @discardableResult
    func apply(settings: RemoteCameraSettings) async -> RemoteCameraSettings {
        let settingsAreLocked = captureSettingsAreLockedForRecording
        let didSuspendPreview = settingsAreLocked ? false : await suspendMonitorPreviewForSettingsChange()
        let appliedSettings = await applySettingsWhileMonitorPreviewIsSuspended(settings)
        activeSettings = appliedSettings
        await resumeMonitorPreviewAfterSettingsChange(if: didSuspendPreview)
        return appliedSettings
    }

    func setMonitorPreviewDeliverySuspended(_ suspended: Bool) {
        previewQueue.async {
            self.previewDelegate.setDeliverySuspended(suspended)
        }
    }

    @discardableResult
    private func applySettingsWhileMonitorPreviewIsSuspended(_ settings: RemoteCameraSettings) async -> RemoteCameraSettings {
        let isCurrentlyRecording = captureSettingsAreLockedForRecording
        let plan = settingsPlanner.requestPlan(
            for: settings,
            isRecording: isCurrentlyRecording,
            activeLens: activeLens,
            activePrefersCinematicDevice: activePrefersCinematicDevice
        )
        if let sessionConfiguration = plan.sessionConfiguration {
            await configureSession(
                lens: sessionConfiguration.lens,
                prefersCinematicDevice: sessionConfiguration.prefersCinematicDevice
            )
            if sessionConfiguration.resetsZoom {
                await setZoomFactor(1)
            }
        }

        var normalizedSettings = settingsPlanner.normalizedSettings(plan.settings, activeDevice: activeDevice)
        if isCurrentlyRecording {
            normalizedSettings = settingsPlanner.preserveActiveCaptureSettings(
                in: normalizedSettings,
                activeLens: activeLens,
                activeCaptureProfileID: activeCaptureProfileID,
                activeCinematicVideoEnabled: activeCinematicVideoEnabled,
                activeCinematicAperture: activeCinematicAperture,
                activeSettings: activeSettings,
                activeDevice: activeDevice
            )
        } else if settingsPlanner.canApplyOnlyCinematicAperture(
            normalizedSettings,
            activeCinematicVideoEnabled: activeCinematicVideoEnabled,
            activeCinematicAperture: activeCinematicAperture,
            activeVideoInput: activeVideoInput
        ) {
            normalizedSettings = await applyCinematicSettings(normalizedSettings)
            refreshCapabilities()
            return normalizedSettings
        } else {
            await applyFormat(normalizedSettings)
            normalizedSettings = settingsPlanner.normalizedSettings(normalizedSettings, activeDevice: activeDevice)
            normalizedSettings.captureProfileID = await applyCaptureCodec(normalizedSettings)
            normalizedSettings = settingsPlanner.normalizedSettings(normalizedSettings, activeDevice: activeDevice)
            normalizedSettings = await applyCinematicSettings(normalizedSettings)
        }
        if isCurrentlyRecording {
            normalizedSettings.zoomFactor = Double(await currentZoomFactor())
        } else {
            normalizedSettings.zoomFactor = Double(await setZoomFactor(1))
        }
        if normalizedSettings.cinematicVideoEnabled {
            normalizedSettings.focusMode = .continuousAuto
        } else {
            await applyFocus(normalizedSettings)
        }
        await applyExposure(normalizedSettings)
        await applyWhiteBalance(normalizedSettings)
        // Changing stabilization or rotation on the movie connection ends a recording in progress.
        if !isCurrentlyRecording {
            await applyStabilization(normalizedSettings.stabilizationMode)
            await applyRotation(degrees: normalizedSettings.rotationDegrees)
        }
        if isCurrentlyRecording {
            normalizedSettings.torchEnabled = await currentTorchEnabled()
        } else {
            _ = await setTorchEnabled(false)
            normalizedSettings.torchEnabled = false
        }
        refreshCapabilities()
        return normalizedSettings
    }

    func refreshCapabilities() {
        if let activeDevice {
            capabilities = capabilityBuilder.makeCapabilities(activeDevice: activeDevice)
        }
    }

    private func suspendMonitorPreviewForSettingsChange() async -> Bool {
        guard isPreviewRunning else { return false }
        await withCheckedContinuation { continuation in
            previewQueue.async {
                self.previewDelegate.setSuspended(true, resetEncoder: true)
                continuation.resume()
            }
        }
        return true
    }

    private func resumeMonitorPreviewAfterSettingsChange(if didSuspendPreview: Bool) async {
        guard didSuspendPreview else { return }
        try? await Task.sleep(for: .milliseconds(250))
        await withCheckedContinuation { continuation in
            previewQueue.async {
                self.previewDelegate.setSuspended(false, resetEncoder: true)
                continuation.resume()
            }
        }
    }

    func runOnSessionQueue<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: body())
            }
        }
    }

    func runThrowingOnSessionQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func movieOutputIsRecording() async -> Bool {
        let movieOutput = movieOutput
        return await runOnSessionQueue {
            movieOutput.isRecording
        }
    }

    func existingRecordingURL(takeID: UUID) -> URL? {
        recordingLibrary.existingRecordingURL(takeID: takeID)
    }

    func pendingRecordingURLs() -> [URL] {
        recordingLibrary.pendingRecordingURLs()
    }

    func removeRecording(at url: URL) {
        recordingLibrary.removeRecording(at: url)
    }
}
