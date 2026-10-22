import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation
import OSLog

@MainActor
extension CameraCaptureController {
    private struct SessionConfigurationResult {
        var device: AVCaptureDevice?
        var videoInput: AVCaptureDeviceInput?
        var audioInput: AVCaptureDeviceInput?
        var statusMessage: String
        var isRunning: Bool
    }

    func makeSessionNotificationObservers() -> [NSObjectProtocol] {
        let center = NotificationCenter.default
        return [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleSessionInterruption(notification)
                }
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleSessionInterruptionEnded()
                }
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handleSessionRuntimeError(notification)
                }
            },
            center.addObserver(
                forName: AVCaptureSession.didStopRunningNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleSessionStopped()
                }
            }
        ]
    }

    private func handleSessionInterruption(_ notification: Notification) {
        let reason = Self.sessionInterruptionReason(from: notification)
        let message = reason ?? "iPhone camera paused"
        setCaptureSessionWarning(message)
        statusMessage = message
        isPreviewRunning = session.isRunning
        Self.logger.warning("\(message, privacy: .public)")
    }

    private func handleSessionInterruptionEnded() async {
        if isRecording {
            statusMessage = "Recording resumed"
            return
        }
        setCaptureSessionWarning(nil)
        await restartSessionIfNeeded(recoveredStatusMessage: "Camera ready")
    }

    private func handleSessionRuntimeError(_ notification: Notification) async {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        let message = error.map { "Camera session error: \($0.localizedDescription)" }
            ?? "Camera session error"
        setCaptureSessionWarning(message)
        statusMessage = message
        isPreviewRunning = session.isRunning
        Self.logger.error("\(message, privacy: .public)")

        if !isRecording, Self.isMediaServicesReset(error) {
            await restartSessionIfNeeded(recoveredStatusMessage: "Camera recovered")
        }
    }

    private func handleSessionStopped() {
        isPreviewRunning = false
        guard isRecording else { return }
        let message = "Camera session stopped while recording"
        setCaptureSessionWarning(message)
        statusMessage = message
        Self.logger.warning("\(message, privacy: .public)")
    }

    private func restartSessionIfNeeded(recoveredStatusMessage: String) async {
        guard activeDevice != nil else { return }
        let didRestart = await runOnSessionQueue { [session] in
            guard !session.isRunning else { return true }
            session.startRunning()
            return session.isRunning
        }
        isPreviewRunning = didRestart
        if didRestart {
            setCaptureSessionWarning(nil)
            statusMessage = recoveredStatusMessage
        }
    }

    func setCaptureSessionWarning(_ warning: String?) {
        guard captureSessionWarning != warning else { return }
        captureSessionWarning = warning
        publishCaptureWarningChanged()
    }

    private static func isMediaServicesReset(_ error: Error?) -> Bool {
        guard let error else { return false }
        if let avError = error as? AVError {
            return avError.code == .mediaServicesWereReset
        }
        let nsError = error as NSError
        return nsError.domain == AVFoundationErrorDomain
            && nsError.code == AVError.Code.mediaServicesWereReset.rawValue
    }

    private static func sessionInterruptionReason(from notification: Notification) -> String? {
        guard let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] else {
            return nil
        }
        let reason: AVCaptureSession.InterruptionReason?
        if let typedReason = rawReason as? AVCaptureSession.InterruptionReason {
            reason = typedReason
        } else if let number = rawReason as? NSNumber {
            reason = AVCaptureSession.InterruptionReason(rawValue: number.intValue)
        } else {
            reason = nil
        }
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            return "iPhone camera is unavailable in the background"
        case .audioDeviceInUseByAnotherClient:
            return "iPhone microphone is in use by another app"
        case .videoDeviceInUseByAnotherClient:
            return "Your Mac is using this iPhone as a Continuity Camera. Choose BlitzRecorder Camera on the Mac to switch"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "iPhone camera is unavailable with multiple foreground apps"
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "iPhone camera paused due to system pressure"
        case .sensitiveContentMitigationActivated:
            return "iPhone camera paused by sensitive-content protection"
        case .none:
            return nil
        @unknown default:
            return "unknown interruption"
        }
    }

    func configureSession(lens: RemoteCameraLens, prefersCinematicDevice: Bool = false) async {
        configurePreviewDelegateCallbacks()
        configureMetadataDelegateCallbacks()
        let sessionQueue = sessionQueue
        let session = session
        let movieOutput = movieOutput
        let previewOutput = previewOutput
        let metadataOutput = metadataOutput
        let previewDelegate = previewDelegate
        let previewQueue = previewQueue
        let metadataDelegate = metadataDelegate
        let metadataQueue = metadataQueue
        let capabilityBuilder = capabilityBuilder
        let result = await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.beginConfiguration()
                session.sessionPreset = .hd1920x1080
                Self.configureHighQualityBluetoothRecordingIfAvailable(session)

                for input in session.inputs {
                    session.removeInput(input)
                }
                Self.configureCinematicMetadataOutputIfNeeded(
                    session: session,
                    metadataOutput: metadataOutput,
                    metadataDelegate: metadataDelegate,
                    metadataQueue: metadataQueue,
                    isEnabled: false
                )

                let preferredDevice: AVCaptureDevice?
                if prefersCinematicDevice {
                    preferredDevice = capabilityBuilder.cinematicDevice(for: lens)
                        ?? capabilityBuilder.device(for: lens)
                } else {
                    preferredDevice = capabilityBuilder.device(for: lens)
                }
                let device = preferredDevice
                    ?? capabilityBuilder.device(for: .wide)
                    ?? AVCaptureDevice.default(for: .video)
                guard let device else {
                    session.commitConfiguration()
                    continuation.resume(returning: SessionConfigurationResult(
                        device: nil,
                        videoInput: nil,
                        audioInput: nil,
                        statusMessage: "No camera available",
                        isRunning: false
                    ))
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if session.canAddInput(input) {
                        session.addInput(input)
                    } else {
                        session.commitConfiguration()
                        continuation.resume(returning: SessionConfigurationResult(
                            device: nil,
                            videoInput: nil,
                            audioInput: nil,
                            statusMessage: "Camera input not available",
                            isRunning: session.isRunning
                        ))
                        return
                    }
                    let audioInput = Self.addAudioInputIfAuthorized(
                        to: session,
                        prefersSpatialAudio: prefersCinematicDevice
                    )
                    if session.canSetSessionPreset(.inputPriority) {
                        session.sessionPreset = .inputPriority
                    }
                    if (try? device.lockForConfiguration()) != nil {
                        Self.enableLensSmudgeDetectionIfAvailable(device)
                        device.unlockForConfiguration()
                    }
                    if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                        session.addOutput(movieOutput)
                    }
                    if prefersCinematicDevice {
                        Self.lockConstituentDeviceSwitchingIfAvailable(for: device)
                        Self.lockRecordingConstituentDeviceSwitchingIfAvailable(for: device, movieOutput: movieOutput)
                    } else {
                        movieOutput.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled = false
                    }
                    Self.configurePreviewOutputIfNeeded(
                        session: session,
                        previewOutput: previewOutput,
                        previewDelegate: previewDelegate,
                        previewQueue: previewQueue
                    )
                    session.commitConfiguration()

                    if !session.isRunning {
                        session.startRunning()
                    }

                    continuation.resume(returning: SessionConfigurationResult(
                        device: device,
                        videoInput: input,
                        audioInput: audioInput,
                        statusMessage: "\(lens.displayName) ready",
                        isRunning: session.isRunning
                    ))
                } catch {
                    session.commitConfiguration()
                    continuation.resume(returning: SessionConfigurationResult(
                        device: nil,
                        videoInput: nil,
                        audioInput: nil,
                        statusMessage: "Camera failed: \(error.localizedDescription)",
                        isRunning: session.isRunning
                    ))
                }
            }
        }

        activeDevice = result.device
        activeVideoInput = result.videoInput
        activeAudioInput = result.audioInput
        activeCinematicVideoEnabled = false
        activeCinematicFocusMetadataEnabled = false
        activeCinematicAperture = nil
        setCinematicFocusMetadataWarning(nil)
        clearCinematicFocusCandidates()
        configureSystemPressureMonitoring(for: result.device)
        configureLensSmudgeMonitoring(for: result.device)
        configureRotationCoordinator(for: result.device)
        configureCinematicSceneMonitoring(for: result.device)
        if result.device != nil {
            activeLens = lens
            activePrefersCinematicDevice = prefersCinematicDevice
        }
        refreshCapabilities()
        statusMessage = result.statusMessage
        isPreviewRunning = result.isRunning
    }

    private nonisolated static func addAudioInputIfAuthorized(
        to session: AVCaptureSession,
        prefersSpatialAudio: Bool
    ) -> AVCaptureDeviceInput? {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio) else {
            return nil
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if prefersSpatialAudio,
               input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) {
                input.multichannelAudioMode = .firstOrderAmbisonics
            }
            if session.canAddInput(input) {
                session.addInput(input)
                return input
            }
        } catch {
        }
        return nil
    }

    private nonisolated static func configureHighQualityBluetoothRecordingIfAvailable(
        _ session: AVCaptureSession
    ) {
        if #available(iOS 26.0, *) {
            session.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true
        }
    }

    private nonisolated static func lockConstituentDeviceSwitchingIfAvailable(for device: AVCaptureDevice) {
        guard device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported else {
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setPrimaryConstituentDeviceSwitchingBehavior(.locked, restrictedSwitchingBehaviorConditions: [])
        } catch {
        }
    }

    private nonisolated static func lockRecordingConstituentDeviceSwitchingIfAvailable(
        for device: AVCaptureDevice,
        movieOutput: AVCaptureMovieFileOutput
    ) {
        guard device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported else {
            movieOutput.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled = false
            return
        }
        movieOutput.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled = true
        movieOutput.setPrimaryConstituentDeviceSwitchingBehaviorForRecording(
            .locked,
            restrictedSwitchingBehaviorConditions: []
        )
    }

    private func configurePreviewDelegateCallbacks() {
        previewDelegate.onFrame = { [weak self] data, width, height in
            Task { @MainActor in
                self?.onMonitorFrame?(data, width, height)
            }
        }
        previewDelegate.onVideoFrame = { [weak self] frame in
            Task { @MainActor in
                self?.onMonitorVideoFrame?(frame)
            }
        }
        previewDelegate.onDroppedFrame = { [weak self] in
            Task { @MainActor in
                self?.onMonitorFrameDropped?()
            }
        }
    }

    private func configureMetadataDelegateCallbacks() {
        metadataDelegate.onCandidates = { [weak self] candidates in
            Task { @MainActor in
                self?.updateCinematicFocusCandidates(candidates)
            }
        }
    }

    private nonisolated static func configurePreviewOutputIfNeeded(
        session: AVCaptureSession,
        previewOutput: AVCaptureVideoDataOutput,
        previewDelegate: CameraMonitorPreviewDelegate,
        previewQueue: DispatchQueue
    ) {
        previewOutput.alwaysDiscardsLateVideoFrames = true
        previewOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if !session.outputs.contains(previewOutput), session.canAddOutput(previewOutput) {
            session.addOutput(previewOutput)
        }
        previewOutput.setSampleBufferDelegate(previewDelegate, queue: previewQueue)
    }
}
