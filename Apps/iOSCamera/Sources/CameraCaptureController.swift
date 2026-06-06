import BlitzRecorderCore
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Observation
import Darwin
import UIKit
import VideoToolbox

@Observable
@MainActor
final class CameraCaptureController {
    let session = AVCaptureSession()

    var isPreviewRunning = false
    var isRecording = false
    var statusMessage = "Camera is off"
    var capabilities: RemoteCameraCapabilities?

    private var activeDevice: AVCaptureDevice?
    private var activeLens: RemoteCameraLens = .wide
    private var activePrefersCinematicDevice = false
    private let movieOutput = AVCaptureMovieFileOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "blitzrecorder.camera-capture-session", qos: .userInitiated)
    private let previewQueue = DispatchQueue(label: "blitzrecorder.camera-monitor-preview")
    private let previewDelegate = CameraMonitorPreviewDelegate()
    private let recordingLibrary = CameraRecordingLibrary()
    private var activeVideoInput: AVCaptureDeviceInput?
    private var recordingDelegate: MovieRecordingDelegate?
    private var activeRecordingURL: URL?
    private var activeCaptureProfileID: RemoteCameraCaptureProfileID = .automatic
    private var activeCaptureCodecLabel: String?
    private var activeCaptureFormatLabel: String?
    private var activeCinematicVideoEnabled = false
    private var activeCinematicAperture: Double?
    private var cinematicSceneObservation: NSKeyValueObservation?
    private var cinematicSceneWarning: String?
    var onMonitorFrame: (@Sendable (Data, Int, Int) -> Void)?
    var onMonitorVideoFrame: (@Sendable (RemoteCameraMonitorVideoFrame) -> Void)?
    var onMonitorFrameDropped: (@Sendable () -> Void)?
    var onRecordingFinishedUnexpectedly: (@Sendable (Result<CameraRecordingResult, Error>) -> Void)?

    var captureWarning: String? {
        if activeCinematicVideoEnabled {
            return cinematicSceneWarning
        }
        return nil
    }

    private var capabilityBuilder: RemoteCameraCaptureCapabilityBuilder {
        RemoteCameraCaptureCapabilityBuilder(movieOutput: movieOutput)
    }

    private var settingsPlanner: CameraCaptureSettingsPlanner {
        CameraCaptureSettingsPlanner(capabilityBuilder: capabilityBuilder)
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

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
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
        guard supportedLenses().contains(lens) else {
            statusMessage = "\(lens.displayName) not available"
            return
        }
        let didSuspendPreview = await suspendMonitorPreviewForSettingsChange()
        await configureSession(lens: lens)
        await setZoomFactor(1)
        await resumeMonitorPreviewAfterSettingsChange(if: didSuspendPreview)
    }

    @discardableResult
    func setZoomFactor(_ zoomFactor: CGFloat) async -> CGFloat {
        guard let activeDevice else { return zoomFactor }
        let result = await runOnSessionQueue {
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                let clamped = min(max(zoomFactor, activeDevice.minAvailableVideoZoomFactor), activeDevice.maxAvailableVideoZoomFactor)
                guard abs(activeDevice.videoZoomFactor - clamped) > 0.0001 else {
                    return (activeDevice.videoZoomFactor, true)
                }
                activeDevice.videoZoomFactor = clamped
                return (activeDevice.videoZoomFactor, true)
            } catch {
                return (activeDevice.videoZoomFactor, false)
            }
        }
        if !result.1 {
            statusMessage = "Zoom not available"
        }
        return result.0
    }

    @discardableResult
    func setTorchEnabled(_ isEnabled: Bool) async -> Bool {
        guard let activeDevice else {
            return false
        }
        guard activeDevice.hasTorch, activeDevice.isTorchAvailable else {
            if isEnabled {
                statusMessage = "Light not available"
            }
            return false
        }

        let result = await runOnSessionQueue {
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                if isEnabled {
                    try activeDevice.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    activeDevice.torchMode = .off
                }
                return (activeDevice.torchMode == .on, true)
            } catch {
                return (activeDevice.torchMode == .on, false)
            }
        }
        if !result.1 {
            statusMessage = "Light not available"
        }
        return result.0
    }

    @discardableResult
    func setRotationDegrees(_ degrees: Int) async -> Int {
        let requestedRotation = RemoteCameraSettings.normalizedRotationDegrees(degrees)
        let supportedRotationDegrees = capabilities?.supportedRotationDegrees ?? [0, 90, 180, 270]
        let rotation = supportedRotationDegrees.contains(requestedRotation)
            ? requestedRotation
            : supportedRotationDegrees.first ?? requestedRotation
        await applyRotation(degrees: rotation)
        return rotation
    }

    @discardableResult
    func apply(settings: RemoteCameraSettings) async -> RemoteCameraSettings {
        let didSuspendPreview = await suspendMonitorPreviewForSettingsChange()
        let appliedSettings = await applySettingsWhileMonitorPreviewIsSuspended(settings)
        await resumeMonitorPreviewAfterSettingsChange(if: didSuspendPreview)
        return appliedSettings
    }

    @discardableResult
    private func applySettingsWhileMonitorPreviewIsSuspended(_ settings: RemoteCameraSettings) async -> RemoteCameraSettings {
        let isCurrentlyRecording = isRecording
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
                activeDevice: activeDevice
            )
        } else if settingsPlanner.canApplyOnlyCinematicAperture(
            normalizedSettings,
            activeCinematicVideoEnabled: activeCinematicVideoEnabled,
            activeCinematicAperture: activeCinematicAperture,
            activeVideoInput: activeVideoInput
        ) {
            normalizedSettings = await applyCinematicSettings(normalizedSettings)
            if let activeDevice {
                capabilities = makeCapabilities(activeDevice: activeDevice)
            }
            return normalizedSettings
        } else {
            await applyFormat(normalizedSettings)
            normalizedSettings = settingsPlanner.normalizedSettings(normalizedSettings, activeDevice: activeDevice)
            normalizedSettings.captureProfileID = await applyCaptureCodec(normalizedSettings)
            normalizedSettings = settingsPlanner.normalizedSettings(normalizedSettings, activeDevice: activeDevice)
            normalizedSettings = await applyCinematicSettings(normalizedSettings)
        }
        normalizedSettings.zoomFactor = Double(await setZoomFactor(1))
        if normalizedSettings.cinematicVideoEnabled {
            normalizedSettings.focusMode = .continuousAuto
        } else {
            await applyFocus(normalizedSettings)
        }
        await applyExposure(normalizedSettings)
        await applyWhiteBalance(normalizedSettings)
        await applyStabilization(
            normalizedSettings.stabilizationMode,
            cinematicVideoEnabled: normalizedSettings.cinematicVideoEnabled
        )
        await applyRotation(degrees: normalizedSettings.rotationDegrees)
        _ = await setTorchEnabled(false)
        normalizedSettings.torchEnabled = false
        if let activeDevice {
            capabilities = makeCapabilities(activeDevice: activeDevice)
        }
        return normalizedSettings
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

    func startRecording(takeID: UUID) async throws -> CameraRecordingStartResult {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            let granted = await requestAccess(for: .audio)
            if granted {
                await configureSession(lens: activeLens, prefersCinematicDevice: activePrefersCinematicDevice)
            }
        }

        let url = try recordingLibrary.recordingURL(takeID: takeID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let delegate = MovieRecordingDelegate()
        delegate.unexpectedCompletion = { [weak self] url, error in
            Task { @MainActor in
                await self?.handleUnexpectedRecordingFinish(url: url, error: error)
            }
        }
        recordingDelegate = delegate
        activeRecordingURL = url
        let session = session
        let movieOutput = movieOutput
        do {
            try await runThrowingOnSessionQueue {
                guard session.isRunning else {
                    throw CameraCaptureError.sessionNotRunning
                }
                guard !movieOutput.isRecording else {
                    throw CameraCaptureError.alreadyRecording
                }
                movieOutput.startRecording(to: url, recordingDelegate: delegate)
            }
            let deviceStartTime = try await delegate.waitForStart()
            isRecording = true
            statusMessage = "Recording"
            return CameraRecordingStartResult(url: url, deviceStartTime: deviceStartTime)
        } catch {
            recordingDelegate = nil
            activeRecordingURL = nil
            throw error
        }
    }

    func waitForCaptureReadiness(timeoutSeconds: TimeInterval = 1.2) async {
        guard activeDevice != nil else { return }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var stableSamples = 0

        while Date() < deadline {
            let isAdjusting = await runOnSessionQueue { [activeDevice] in
                guard let activeDevice else { return false }
                return activeDevice.isAdjustingFocus
                    || activeDevice.isAdjustingExposure
                    || activeDevice.isAdjustingWhiteBalance
            }
            if isAdjusting {
                stableSamples = 0
            } else {
                stableSamples += 1
                if stableSamples >= 2 {
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func configureCinematicSceneMonitoring(for device: AVCaptureDevice?) {
        cinematicSceneObservation?.invalidate()
        cinematicSceneObservation = nil
        cinematicSceneWarning = nil
        guard #available(iOS 26.0, *),
              let device else {
            return
        }
        cinematicSceneObservation = device.observe(
            \.cinematicVideoCaptureSceneMonitoringStatuses,
            options: [.initial, .new]
        ) { [weak self] _, change in
            let statuses = change.newValue ?? []
            Task { @MainActor in
                self?.updateCinematicSceneWarning(statuses)
            }
        }
    }

    @available(iOS 26.0, *)
    private func updateCinematicSceneWarning(_ statuses: Set<AVCaptureSceneMonitoringStatus>) {
        if statuses.contains(.notEnoughLight) {
            cinematicSceneWarning = "Cinematic needs more light"
        } else {
            cinematicSceneWarning = nil
        }
    }

    func stopRecording() async throws -> CameraRecordingResult {
        let movieOutput = movieOutput
        let outputIsRecording = await runOnSessionQueue {
            movieOutput.isRecording
        }
        guard outputIsRecording else {
            guard let activeRecordingURL else {
                throw CameraCaptureError.notRecording
            }
            return try await CameraRecordingResult(url: activeRecordingURL)
        }
        guard let delegate = recordingDelegate else {
            throw CameraCaptureError.notRecording
        }

        return try await withCheckedThrowingContinuation { continuation in
            delegate.completion = { [weak self] result in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume(throwing: CameraCaptureError.notRecording)
                        return
                    }
                    let finishedURL = self.activeRecordingURL ?? delegate.outputFileURL
                    self.isRecording = false
                    self.recordingDelegate = nil
                    self.activeRecordingURL = nil
                    switch result {
                    case .success(let url):
                        do {
                            continuation.resume(returning: try await CameraRecordingResult(url: url))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        if let url = finishedURL,
                           self.recordingLibrary.hasRecoverableMedia(at: url) {
                            do {
                                continuation.resume(returning: try await CameraRecordingResult(
                                    url: url,
                                    stopReason: error.localizedDescription
                                ))
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            sessionQueue.async {
                movieOutput.stopRecording()
            }
            statusMessage = "Stopping recording"
        }
    }

    private func handleUnexpectedRecordingFinish(url: URL, error: Error?) async {
        isRecording = false
        recordingDelegate = nil
        activeRecordingURL = url
        let result: Result<CameraRecordingResult, Error>
        if recordingLibrary.hasRecoverableMedia(at: url) {
            do {
                result = .success(try await CameraRecordingResult(
                    url: url,
                    stopReason: error?.localizedDescription
                ))
            } catch {
                result = .failure(error)
            }
        } else if let error {
            result = .failure(error)
        } else {
            result = .failure(CameraCaptureError.notRecording)
        }
        onRecordingFinishedUnexpectedly?(result)
    }

    private struct SessionConfigurationResult {
        var device: AVCaptureDevice?
        var videoInput: AVCaptureDeviceInput?
        var statusMessage: String
        var isRunning: Bool
    }

    private func runOnSessionQueue<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: body())
            }
        }
    }

    private func runThrowingOnSessionQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
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

    private func configureSession(lens: RemoteCameraLens, prefersCinematicDevice: Bool = false) async {
        configurePreviewDelegateCallbacks()
        let sessionQueue = sessionQueue
        let session = session
        let movieOutput = movieOutput
        let previewOutput = previewOutput
        let previewDelegate = previewDelegate
        let previewQueue = previewQueue
        let capabilityBuilder = capabilityBuilder
        let result = await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.beginConfiguration()
                session.sessionPreset = .hd1920x1080

                for input in session.inputs {
                    session.removeInput(input)
                }

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
                            statusMessage: "Camera input not available",
                            isRunning: session.isRunning
                        ))
                        return
                    }
                    Self.addAudioInputIfAuthorized(to: session)
                    if session.canSetSessionPreset(.inputPriority) {
                        session.sessionPreset = .inputPriority
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
                        statusMessage: "\(lens.displayName) ready",
                        isRunning: session.isRunning
                    ))
                } catch {
                    session.commitConfiguration()
                    continuation.resume(returning: SessionConfigurationResult(
                        device: nil,
                        videoInput: nil,
                        statusMessage: "Camera failed: \(error.localizedDescription)",
                        isRunning: session.isRunning
                    ))
                }
            }
        }

        activeDevice = result.device
        activeVideoInput = result.videoInput
        activeCinematicVideoEnabled = false
        activeCinematicAperture = nil
        configureCinematicSceneMonitoring(for: result.device)
        if result.device != nil {
            activeLens = lens
            activePrefersCinematicDevice = prefersCinematicDevice
        }
        if let device = result.device {
            capabilities = makeCapabilities(activeDevice: device)
        }
        statusMessage = result.statusMessage
        isPreviewRunning = result.isRunning
    }

    private nonisolated static func addAudioInputIfAuthorized(to session: AVCaptureSession) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio) else {
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
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

    private func device(for lens: RemoteCameraLens) -> AVCaptureDevice? {
        capabilityBuilder.device(for: lens)
    }

    private func cinematicDevice(for lens: RemoteCameraLens) -> AVCaptureDevice? {
        capabilityBuilder.cinematicDevice(for: lens)
    }

    private func supportedLenses() -> [RemoteCameraLens] {
        capabilityBuilder.supportedLenses()
    }

    private func makeCapabilities(activeDevice: AVCaptureDevice) -> RemoteCameraCapabilities {
        capabilityBuilder.makeCapabilities(activeDevice: activeDevice)
    }

    private func cinematicCapabilities() -> (
        supportsCinematicVideo: Bool,
        minimumAperture: Double?,
        maximumAperture: Double?,
        defaultAperture: Double?
    ) {
        let cinematic = capabilityBuilder.cinematicCapabilities(activeVideoInputDevice: activeVideoInput?.device)
        return (
            cinematic.supportsCinematicVideo,
            cinematic.minimumAperture,
            cinematic.maximumAperture,
            cinematic.defaultAperture
        )
    }

    private struct CinematicApertureRange {
        var minimum: Double
        var maximum: Double
        var `default`: Double
    }

    private func activeCinematicApertureRange(for device: AVCaptureDevice) -> CinematicApertureRange? {
        guard #available(iOS 26.0, *) else { return nil }
        let minimum = Double(device.activeFormat.minSimulatedAperture)
        let maximum = Double(device.activeFormat.maxSimulatedAperture)
        let defaultAperture = Double(device.activeFormat.defaultSimulatedAperture)
        guard minimum.isFinite,
              maximum.isFinite,
              defaultAperture.isFinite,
              minimum > 0,
              maximum >= minimum else {
            return nil
        }
        return CinematicApertureRange(
            minimum: minimum,
            maximum: maximum,
            default: min(maximum, max(minimum, defaultAperture))
        )
    }

    private func resolvedCinematicAperture(
        requested: Double?,
        on device: AVCaptureDevice
    ) -> Double? {
        guard let range = activeCinematicApertureRange(for: device) else {
            return nil
        }
        let aperture = requested ?? range.default
        guard aperture.isFinite else {
            return range.default
        }
        return min(range.maximum, max(range.minimum, aperture))
    }

    private func applyCinematicSettings(_ settings: RemoteCameraSettings) async -> RemoteCameraSettings {
        var appliedSettings = settings
        guard let activeVideoInput else {
            appliedSettings.cinematicVideoEnabled = false
            appliedSettings.cinematicAperture = nil
            return appliedSettings
        }
        guard #available(iOS 26.0, *),
              activeVideoInput.isCinematicVideoCaptureSupported else {
            appliedSettings.cinematicVideoEnabled = false
            appliedSettings.cinematicAperture = nil
            activeCinematicVideoEnabled = false
            activeCinematicAperture = nil
            return appliedSettings
        }

        if appliedSettings.cinematicVideoEnabled {
            appliedSettings.cinematicAperture = resolvedCinematicAperture(
                requested: appliedSettings.cinematicAperture,
                on: activeVideoInput.device
            )
        } else {
            appliedSettings.cinematicAperture = nil
        }

        let session = session
        let movieOutput = movieOutput
        let enabled = appliedSettings.cinematicVideoEnabled
        let aperture = appliedSettings.cinematicAperture
        if enabled == activeCinematicVideoEnabled,
           CameraCaptureSettingsPlanner.cinematicAperturesMatch(aperture, activeCinematicAperture) {
            return appliedSettings
        }
        let outputIsRecording = await runOnSessionQueue {
            movieOutput.isRecording
        }
        guard !outputIsRecording else {
            appliedSettings.cinematicVideoEnabled = activeCinematicVideoEnabled
            appliedSettings.cinematicAperture = activeCinematicAperture
            statusMessage = "Cinematic settings apply after recording stops"
            return appliedSettings
        }

        await runOnSessionQueue {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            if enabled,
               let aperture {
                activeVideoInput.simulatedAperture = Float(aperture)
            }
            activeVideoInput.isCinematicVideoCaptureEnabled = enabled
        }

        activeCinematicVideoEnabled = enabled
        activeCinematicAperture = enabled ? aperture : nil
        if !enabled {
            cinematicSceneWarning = nil
        }
        appliedSettings.cinematicVideoEnabled = enabled
        appliedSettings.cinematicAperture = enabled ? aperture : nil
        return appliedSettings
    }

    private func activeFrameRate(for device: AVCaptureDevice) -> Int {
        let seconds = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return max(1, Int((1 / seconds).rounded()))
    }

    private func applyFormat(_ settings: RemoteCameraSettings) async {
        guard let activeDevice,
              let formatID = settings.formatID,
              let format = captureFormat(for: settings, device: activeDevice) else {
            return
        }

        let colorSpace = Self.captureColorSpace(for: settings.colorMode, format: format)
        if activeFormatMatches(format, on: activeDevice, frameRate: settings.frameRate),
           activeColorSpaceMatches(colorSpace, on: activeDevice) {
            activeCaptureFormatLabel = "\(formatID) @ \(settings.frameRate) fps"
            return
        }

        let session = session
        let applied = await runOnSessionQueue { () -> Bool in
            do {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                session.automaticallyConfiguresCaptureDeviceForWideColor = colorSpace == nil
                activeDevice.activeFormat = format
                if let colorSpace {
                    activeDevice.activeColorSpace = colorSpace
                } else if activeDevice.activeColorSpace == .appleLog
                    || Self.isAppleLog2(activeDevice.activeColorSpace) {
                    activeDevice.activeColorSpace = .sRGB
                }
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, settings.frameRate)))
                activeDevice.activeVideoMinFrameDuration = frameDuration
                activeDevice.activeVideoMaxFrameDuration = frameDuration
                return true
            } catch {
                return false
            }
        }
        if applied {
            activeCaptureFormatLabel = "\(formatID) @ \(settings.frameRate) fps"
        } else {
            statusMessage = "Format not available"
        }
    }

    private func captureFormat(for settings: RemoteCameraSettings, device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        guard let formatID = settings.formatID else { return nil }
        return RemoteCameraCaptureProfileResolver.captureFormat(
            for: settings.captureProfileID,
            formatID: formatID,
            frameRate: settings.frameRate,
            device: device,
            colorMode: settings.colorMode,
            requiresCinematic: settings.cinematicVideoEnabled
        )
    }

    private func activeFormatMatches(
        _ format: AVCaptureDevice.Format,
        on device: AVCaptureDevice,
        frameRate: Int
    ) -> Bool {
        captureFormatsMatch(device.activeFormat, format) && activeFrameRate(for: device) == frameRate
    }

    private func activeColorSpaceMatches(_ colorSpace: AVCaptureColorSpace?, on device: AVCaptureDevice) -> Bool {
        guard let colorSpace else {
            return device.activeColorSpace != .appleLog && !Self.isAppleLog2(device.activeColorSpace)
        }
        return device.activeColorSpace == colorSpace
    }

    private func captureFormatsMatch(_ lhs: AVCaptureDevice.Format, _ rhs: AVCaptureDevice.Format) -> Bool {
        guard CMFormatDescriptionEqual(lhs.formatDescription, otherFormatDescription: rhs.formatDescription) else {
            return false
        }
        if #available(iOS 26.0, *) {
            return lhs.isCinematicVideoCaptureSupported == rhs.isCinematicVideoCaptureSupported
                && abs(lhs.minSimulatedAperture - rhs.minSimulatedAperture) < 0.001
                && abs(lhs.maxSimulatedAperture - rhs.maxSimulatedAperture) < 0.001
                && abs(lhs.defaultSimulatedAperture - rhs.defaultSimulatedAperture) < 0.001
        }
        return true
    }

    private func applyCaptureCodec(_ settings: RemoteCameraSettings) async -> RemoteCameraCaptureProfileID {
        let movieOutput = movieOutput
        let result = await runOnSessionQueue { () -> (RemoteCameraCaptureProfileID, String?) in
            guard let connection = movieOutput.connection(with: .video) else {
                return (.automatic, nil)
            }

            let resolved = RemoteCameraCaptureProfileResolver.resolveCodec(
                requestedProfileID: settings.captureProfileID,
                movieOutput: movieOutput
            )
            if let codec = resolved.codec {
                movieOutput.setOutputSettings([AVVideoCodecKey: codec.rawValue], for: connection)
            }
            return (resolved.profileID, resolved.codecLabel)
        }
        activeCaptureProfileID = result.0
        activeCaptureCodecLabel = result.1
        return result.0
    }

    private static func captureColorSpace(
        for colorMode: RemoteCameraColorMode,
        format: AVCaptureDevice.Format
    ) -> AVCaptureColorSpace? {
        switch colorMode {
        case .standard:
            return nil
        case .appleLog:
            return format.supportedColorSpaces.contains(.appleLog) ? .appleLog : nil
        case .appleLog2:
            if #available(iOS 26.0, *), format.supportedColorSpaces.contains(.appleLog2) {
                return .appleLog2
            }
            return nil
        }
    }

    private static func isAppleLog2(_ colorSpace: AVCaptureColorSpace) -> Bool {
        if #available(iOS 26.0, *) {
            return colorSpace == .appleLog2
        }
        return false
    }

    private func applyFocus(_ settings: RemoteCameraSettings) async {
        guard let activeDevice else { return }
        let applied = await runOnSessionQueue { () -> Bool in
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                switch settings.focusMode {
                case .continuousAuto:
                    if activeDevice.isFocusModeSupported(.continuousAutoFocus) {
                        activeDevice.focusMode = .continuousAutoFocus
                    }
                case .locked:
                    if activeDevice.isFocusModeSupported(.locked) {
                        activeDevice.focusMode = .locked
                    }
                case .manual:
                    if activeDevice.isLockingFocusWithCustomLensPositionSupported {
                        activeDevice.setFocusModeLocked(
                            lensPosition: Float(min(1, max(0, settings.focusPosition))),
                            completionHandler: nil
                        )
                    }
                }
                return true
            } catch {
                return false
            }
        }
        if !applied {
            statusMessage = "Focus not available"
        }
    }

    private func applyExposure(_ settings: RemoteCameraSettings) async {
        guard let activeDevice else { return }
        let applied = await runOnSessionQueue { () -> Bool in
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }

                switch settings.exposureMode {
                case .continuousAuto:
                    if activeDevice.isExposureModeSupported(.continuousAutoExposure) {
                        activeDevice.exposureMode = .continuousAutoExposure
                    }
                    Self.applyExposureTargetBias(settings.exposureBias, to: activeDevice)
                case .locked:
                    Self.applyExposureTargetBias(settings.exposureBias, to: activeDevice)
                    if activeDevice.isExposureModeSupported(.locked) {
                        activeDevice.exposureMode = .locked
                    }
                case .manual:
                    Self.applyExposureTargetBias(settings.exposureBias, to: activeDevice)
                    if activeDevice.isExposureModeSupported(.custom) {
                        let iso = Float(min(
                            max(settings.iso ?? Double(activeDevice.iso), Double(activeDevice.activeFormat.minISO)),
                            Double(activeDevice.activeFormat.maxISO)
                        ))
                        let defaultDuration = CMTimeGetSeconds(activeDevice.exposureDuration)
                        let minDuration = CMTimeGetSeconds(activeDevice.activeFormat.minExposureDuration)
                        let maxDuration = CMTimeGetSeconds(activeDevice.activeFormat.maxExposureDuration)
                        let seconds = min(max(settings.shutterDurationSeconds ?? defaultDuration, minDuration), maxDuration)
                        activeDevice.setExposureModeCustom(
                            duration: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
                            iso: iso,
                            completionHandler: nil
                        )
                    }
                }
                return true
            } catch {
                return false
            }
        }
        if !applied {
            statusMessage = "Exposure not available"
        }
    }

    private static func applyExposureTargetBias(_ exposureBias: Double, to device: AVCaptureDevice) {
        guard device.minExposureTargetBias < device.maxExposureTargetBias else { return }
        let bias = Float(min(
            Double(device.maxExposureTargetBias),
            max(Double(device.minExposureTargetBias), exposureBias)
        ))
        device.setExposureTargetBias(bias, completionHandler: nil)
    }

    private func applyWhiteBalance(_ settings: RemoteCameraSettings) async {
        guard let activeDevice else { return }
        let applied = await runOnSessionQueue { () -> Bool in
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                switch settings.whiteBalanceMode {
                case .continuousAuto:
                    if activeDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        activeDevice.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                case .locked:
                    if activeDevice.isWhiteBalanceModeSupported(.locked) {
                        activeDevice.whiteBalanceMode = .locked
                    }
                case .manual:
                    if activeDevice.isWhiteBalanceModeSupported(.locked) {
                        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                            temperature: Float(settings.whiteBalanceTemperature),
                            tint: Float(settings.whiteBalanceTint)
                        )
                        let gains = Self.clampedWhiteBalanceGains(
                            activeDevice.deviceWhiteBalanceGains(for: values),
                            for: activeDevice
                        )
                        activeDevice.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                    }
                }
                return true
            } catch {
                return false
            }
        }
        if !applied {
            statusMessage = "White balance not available"
        }
    }

    private func applyStabilization(
        _ mode: RemoteCameraStabilizationMode,
        cinematicVideoEnabled: Bool
    ) async {
        let movieOutput = movieOutput
        let previewOutput = previewOutput
        let activeDevice = activeDevice
        await runOnSessionQueue {
            let avMode = Self.movieStabilizationMode(
                for: mode,
                cinematicVideoEnabled: cinematicVideoEnabled,
                activeFormat: activeDevice?.activeFormat
            )
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = avMode
            }
            if let connection = previewOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        }
    }

    private static func movieStabilizationMode(
        for mode: RemoteCameraStabilizationMode,
        cinematicVideoEnabled: Bool,
        activeFormat: AVCaptureDevice.Format?
    ) -> AVCaptureVideoStabilizationMode {
        if cinematicVideoEnabled,
           mode != .off,
           mode != .standard,
           let activeFormat {
            if #available(iOS 13.0, *),
               activeFormat.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced) {
                return .cinematicExtendedEnhanced
            }
            if activeFormat.isVideoStabilizationModeSupported(.cinematic) {
                return .cinematic
            }
        }
        return switch mode {
        case .off: .off
        case .standard: .standard
        case .cinematic: .cinematic
        case .auto: .auto
        }
    }

    private func applyRotation(degrees: Int) async {
        let rotation = CGFloat(RemoteCameraSettings.normalizedRotationDegrees(degrees))
        let movieOutput = movieOutput
        let previewOutput = previewOutput
        await runOnSessionQueue {
            for connection in [movieOutput.connection(with: .video), previewOutput.connection(with: .video)].compactMap({ $0 }) {
                if connection.isVideoRotationAngleSupported(rotation) {
                    connection.videoRotationAngle = rotation
                }
            }
        }
    }

    private func supportedStabilizationModes() -> [RemoteCameraStabilizationMode] {
        guard let activeDevice else { return capabilityBuilder.supportedStabilizationModes() }
        return capabilityBuilder.supportedStabilizationModes(for: activeDevice.activeFormat)
    }

    private func supportedStabilizationModes(for format: AVCaptureDevice.Format) -> [RemoteCameraStabilizationMode] {
        capabilityBuilder.supportedStabilizationModes(for: format)
    }

    private func supportedRotationDegrees() -> [Int] {
        let connection = movieOutput.connection(with: .video) ?? previewOutput.connection(with: .video)
        let supported = [0, 90, 180, 270].filter { degrees in
            connection?.isVideoRotationAngleSupported(CGFloat(degrees)) == true
        }
        if supported.count > 1 {
            return supported
        }
        return supported.isEmpty ? [0] : supported
    }

    private static func clampedWhiteBalanceGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        let maximumGain = device.maxWhiteBalanceGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(gains.redGain, 1), maximumGain),
            greenGain: min(max(gains.greenGain, 1), maximumGain),
            blueGain: min(max(gains.blueGain, 1), maximumGain)
        )
    }

    private func configurePreviewDelegateCallbacks() {
        previewDelegate.onFrame = { [weak self] data, width, height in
            Task { @MainActor in
                self?.publishMonitorFrame(data: data, width: width, height: height)
            }
        }
        previewDelegate.onVideoFrame = { [weak self] frame in
            Task { @MainActor in
                self?.publishMonitorVideoFrame(frame)
            }
        }
        previewDelegate.onDroppedFrame = { [weak self] in
            Task { @MainActor in
                self?.onMonitorFrameDropped?()
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

    private func publishMonitorFrame(data: Data, width: Int, height: Int) {
        onMonitorFrame?(data, width, height)
    }

    private func publishMonitorVideoFrame(_ frame: RemoteCameraMonitorVideoFrame) {
        onMonitorVideoFrame?(frame)
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

    var captureProfileID: RemoteCameraCaptureProfileID {
        activeCaptureProfileID
    }

    var captureCodecLabel: String? {
        activeCaptureCodecLabel
    }

    var captureFormatLabel: String? {
        activeCaptureFormatLabel
    }

    fileprivate static func formatID(for format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height)"
    }
}

private final class CameraMonitorPreviewDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let context = CIContext()
    private lazy var videoEncoder = CameraMonitorPreviewVideoEncoder()
    private var lastEncodedFrameDate = Date.distantPast
    private var isSuspended = false
    private let minimumFrameInterval: TimeInterval = 1.0 / 15.0
    var onFrame: (@Sendable (Data, Int, Int) -> Void)?
    var onVideoFrame: (@Sendable (RemoteCameraMonitorVideoFrame) -> Void)?
    var onDroppedFrame: (@Sendable () -> Void)?

    func setSuspended(_ suspended: Bool, resetEncoder: Bool) {
        isSuspended = suspended
        lastEncodedFrameDate = .distantPast
        if resetEncoder {
            videoEncoder.reset()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isSuspended else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastEncodedFrameDate) >= minimumFrameInterval else {
            return
        }
        lastEncodedFrameDate = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        videoEncoder.onFrame = onVideoFrame
        if videoEncoder.encode(sampleBuffer: sampleBuffer, pixelBuffer: pixelBuffer) {
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let targetWidth = 640
        let scale = CGFloat(targetWidth) / max(image.extent.width, 1)
        let targetHeight = max(1, Int(image.extent.height * scale))
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let outputRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        guard let cgImage = context.createCGImage(scaledImage, from: outputRect),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.58) else {
            return
        }

        onFrame?(data, targetWidth, targetHeight)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onDroppedFrame?()
    }
}

private final class CameraMonitorPreviewVideoEncoder: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var compressionSession: VTCompressionSession?
    private var pixelBufferPool: CVPixelBufferPool?
    private var encodedWidth = 0
    private var encodedHeight = 0
    private var sequenceNumber: Int64 = 0
    private var didFail = false

    var onFrame: (@Sendable (RemoteCameraMonitorVideoFrame) -> Void)?

    func reset() {
        compressionSession.map { VTCompressionSessionInvalidate($0) }
        compressionSession = nil
        pixelBufferPool = nil
        encodedWidth = 0
        encodedHeight = 0
        didFail = false
    }

    func encode(sampleBuffer: CMSampleBuffer, pixelBuffer sourcePixelBuffer: CVPixelBuffer) -> Bool {
        guard !didFail else { return false }

        let sourceWidth = CVPixelBufferGetWidth(sourcePixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourcePixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return false }

        let targetWidth = 640
        let scaledHeight = Int((Double(sourceHeight) * Double(targetWidth) / Double(sourceWidth)).rounded())
        let targetHeight = max(2, scaledHeight + (scaledHeight % 2))

        guard configureIfNeeded(width: targetWidth, height: targetHeight),
              let outputPixelBuffer = makeOutputPixelBuffer(width: targetWidth, height: targetHeight) else {
            didFail = true
            return false
        }

        let image = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let scale = CGFloat(targetWidth) / max(image.extent.width, 1)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        context.render(
            scaledImage,
            to: outputPixelBuffer,
            bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            colorSpace: colorSpace
        )

        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let pts = sourcePTS.isValid ? sourcePTS : CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1_000_000)
        var flags: VTEncodeInfoFlags = []
        let status = VTCompressionSessionEncodeFrame(
            compressionSession!,
            imageBuffer: outputPixelBuffer,
            presentationTimeStamp: pts,
            duration: CMTime(value: 1, timescale: 15),
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        if status != noErr {
            didFail = true
            return false
        }
        return true
    }

    private func configureIfNeeded(width: Int, height: Int) -> Bool {
        guard compressionSession == nil || width != encodedWidth || height != encodedHeight else {
            return true
        }

        compressionSession.map { VTCompressionSessionInvalidate($0) }
        compressionSession = nil
        pixelBufferPool = nil
        encodedWidth = width
        encodedHeight = height

        let encoderSpec = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl as String: true
        ] as CFDictionary
        let sourceAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec,
            imageBufferAttributes: sourceAttributes,
            compressedDataAllocator: nil,
            outputCallback: Self.compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            return false
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 15 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 800_000 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 30 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session

        let poolAttributes = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ] as CFDictionary
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes, sourceAttributes, &pixelBufferPool)
        return pixelBufferPool != nil
    }

    private func makeOutputPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            if pixelBuffer != nil {
                return pixelBuffer
            }
        }
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer)
        return pixelBuffer
    }

    private static let compressionOutputCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
        guard status == noErr,
              let refcon,
              let sampleBuffer else {
            return
        }
        let encoder = Unmanaged<CameraMonitorPreviewVideoEncoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handleEncodedSampleBuffer(sampleBuffer)
    }

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        let byteCount = CMBlockBufferGetDataLength(dataBuffer)
        guard byteCount > 0 else { return }

        var data = Data(count: byteCount)
        let copyStatus = data.withUnsafeMutableBytes { rawBuffer in
            CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: rawBuffer.baseAddress!
            )
        }
        guard copyStatus == noErr else { return }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        let isKeyFrame: Bool
        if let attachments,
           CFArrayGetCount(attachments) > 0,
           let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary?.self) {
            isKeyFrame = !CFDictionaryContainsKey(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()
            )
        } else {
            isKeyFrame = true
        }

        var sps: Data?
        var pps: Data?
        if isKeyFrame {
            sps = h264ParameterSetData(from: formatDescription, index: 0)
            pps = h264ParameterSetData(from: formatDescription, index: 1)
        }

        sequenceNumber += 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frame = RemoteCameraMonitorVideoFrame(
            codec: .h264,
            data: data,
            width: encodedWidth,
            height: encodedHeight,
            presentationTimeSeconds: pts.isValid ? CMTimeGetSeconds(pts) : CACurrentMediaTime(),
            isKeyFrame: isKeyFrame,
            sequenceNumber: sequenceNumber,
            h264SPS: sps,
            h264PPS: pps
        )
        onFrame?(frame)
    }

    private func h264ParameterSetData(from formatDescription: CMFormatDescription, index: Int) -> Data? {
        var parameterSetPointer: UnsafePointer<UInt8>?
        var parameterSetSize = 0
        var parameterSetCount = 0
        var nalUnitHeaderLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: index,
            parameterSetPointerOut: &parameterSetPointer,
            parameterSetSizeOut: &parameterSetSize,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )
        guard status == noErr, let parameterSetPointer, parameterSetSize > 0 else {
            return nil
        }
        return Data(bytes: parameterSetPointer, count: parameterSetSize)
    }
}

enum RemoteCameraCaptureProfileResolver {
    static func supportedProfiles(
        for device: AVCaptureDevice,
        movieOutput: AVCaptureMovieFileOutput
    ) -> [RemoteCameraCaptureProfile] {
        let formats = remoteFormats(for: device)
        let availableCodecs = movieOutput.availableVideoCodecTypes
        let proResFormatFrameRates = proResRemoteFormatFrameRates(for: device)
        let proResFormatIDs = Array(proResFormatFrameRates.keys).sorted()
        let hasProResFormat = !proResFormatIDs.isEmpty
        let hasProResCodec = availableCodecs.contains(.proRes422)
        let hasProResStorage = hasMinimumProResStorageHeadroom()
        let proResReason: String? = if !hasProResFormat {
            "This iPhone camera does not expose a ProRes 422 capture format."
        } else if !hasProResCodec {
            "ProRes 422 is not available for the current camera configuration."
        } else if !hasProResStorage {
            "Free at least 10% iPhone storage for ProRes."
        } else {
            nil
        }

        return [
            RemoteCameraCaptureProfile(
                id: .automatic,
                displayName: "Auto",
                codecLabel: preferredAutomaticCodec(from: availableCodecs).map(Self.codecLabel)
            ),
            RemoteCameraCaptureProfile(
                id: .highEfficiency,
                displayName: "HEVC",
                isAvailable: availableCodecs.contains(.hevc),
                unavailableReason: availableCodecs.contains(.hevc) ? nil : "HEVC is not available.",
                codecLabel: "HEVC",
                supportedFormatIDs: formats.map(\.id),
                supportedFormatFrameRates: Dictionary(uniqueKeysWithValues: formats.map { ($0.id, $0.frameRates) })
            ),
            RemoteCameraCaptureProfile(
                id: .proRes422,
                displayName: "ProRes",
                isAvailable: proResReason == nil,
                unavailableReason: proResReason,
                codecLabel: "ProRes 422",
                supportedFormatIDs: proResFormatIDs,
                supportedFormatFrameRates: proResFormatFrameRates
            )
        ]
    }

    static func formats(
        _ formats: [RemoteCameraFormat],
        supportedBy profileID: RemoteCameraCaptureProfileID,
        profiles: [RemoteCameraCaptureProfile]
    ) -> [RemoteCameraFormat] {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              !profile.supportedFormatIDs.isEmpty else {
            return formats
        }
        let supportedIDs = Set(profile.supportedFormatIDs)
        return formats.filter { supportedIDs.contains($0.id) }
    }

    static func captureFormat(
        for profileID: RemoteCameraCaptureProfileID,
        formatID: String,
        frameRate: Int,
        device: AVCaptureDevice,
        colorMode: RemoteCameraColorMode = .standard,
        requiresCinematic: Bool = false
    ) -> AVCaptureDevice.Format? {
        let candidates = profileID == .proRes422 ? proResCaptureFormats(for: device) : device.formats
        return candidates.first { format in
            Self.formatID(for: format) == formatID
                && (!requiresCinematic || Self.formatSupportsCinematicVideoCapture(format))
                && Self.format(format, supports: colorMode)
                && format.videoSupportedFrameRateRanges.contains { range in
                    range.minFrameRate <= Double(frameRate)
                        && range.maxFrameRate >= Double(frameRate)
                }
        }
    }

    static func preferredCinematicCaptureFormat(
        for device: AVCaptureDevice,
        preferredFrameRate: Int
    ) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter(Self.formatSupportsCinematicVideoCapture)
        return candidates.first { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= Double(preferredFrameRate)
                    && range.maxFrameRate >= Double(preferredFrameRate)
            }
        } ?? candidates.first { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= 30 && range.maxFrameRate >= 30
            }
        } ?? candidates.first
    }

    static func resolveCodec(
        requestedProfileID: RemoteCameraCaptureProfileID,
        movieOutput: AVCaptureMovieFileOutput
    ) -> (profileID: RemoteCameraCaptureProfileID, codec: AVVideoCodecType?, codecLabel: String?) {
        let availableCodecs = movieOutput.availableVideoCodecTypes
        switch requestedProfileID {
        case .automatic:
            let codec = preferredAutomaticCodec(from: availableCodecs)
            return (.automatic, codec, codec.map(codecLabel))
        case .highEfficiency:
            guard availableCodecs.contains(.hevc) else {
                let codec = availableCodecs.first
                return (.automatic, codec, codec.map(codecLabel))
            }
            return (.highEfficiency, .hevc, "HEVC")
        case .proRes422:
            guard availableCodecs.contains(.proRes422) else {
                let codec = availableCodecs.first
                return (.automatic, codec, codec.map(codecLabel))
            }
            return (.proRes422, .proRes422, "ProRes 422")
        }
    }

    private static func remoteFormats(for device: AVCaptureDevice) -> [RemoteCameraFormat] {
        Array(
            Dictionary(grouping: device.formats, by: Self.formatID(for:))
                .compactMap { key, formats -> RemoteCameraFormat? in
                    guard let first = formats.first else { return nil }
                    let dimensions = CMVideoFormatDescriptionGetDimensions(first.formatDescription)
                    let frameRates = supportedRemoteFrameRates(for: formats)
                    guard !frameRates.isEmpty else { return nil }
                    let colorModeFrameRates = supportedColorModeFrameRates(for: formats)
                    return RemoteCameraFormat(
                        id: key,
                        width: Int(dimensions.width),
                        height: Int(dimensions.height),
                        frameRates: frameRates,
                        colorModes: supportedColorModes(from: colorModeFrameRates),
                        colorModeFrameRates: colorModeFrameRates,
                        supportsStabilization: formats.contains(where: Self.formatSupportsStabilization),
                        supportsHDR: formats.contains { $0.isVideoHDRSupported }
                    )
                }
                .sorted { lhs, rhs in
                    let lhsArea = lhs.width * lhs.height
                    let rhsArea = rhs.width * rhs.height
                    if lhsArea == rhsArea {
                        return lhs.id < rhs.id
                    }
                    return lhsArea > rhsArea
                }
                .prefix(8)
        )
    }

    private static func proResRemoteFormatFrameRates(for device: AVCaptureDevice) -> [String: [Int]] {
        Dictionary(grouping: proResCaptureFormats(for: device), by: Self.formatID(for:))
            .mapValues(supportedRemoteFrameRates)
            .filter { !$0.value.isEmpty }
    }

    private static func proResCaptureFormats(for device: AVCaptureDevice) -> [AVCaptureDevice.Format] {
        device.formats.filter(isProResSourceFormat)
    }

    private static func isProResSourceFormat(_ format: AVCaptureDevice.Format) -> Bool {
        format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
    }

    private static func supportedRemoteFrameRates(for formats: [AVCaptureDevice.Format]) -> [Int] {
        Array(Set(formats.flatMap { format in
            format.videoSupportedFrameRateRanges.flatMap { range in
                preferredFrameRates.filter { range.minFrameRate <= Double($0) && range.maxFrameRate >= Double($0) }
            }
        })).sorted()
    }

    private static func supportedColorModeFrameRates(for formats: [AVCaptureDevice.Format]) -> [RemoteCameraColorMode: [Int]] {
        var result: [RemoteCameraColorMode: Set<Int>] = [.standard: Set(supportedRemoteFrameRates(for: formats))]
        for format in formats {
            let frameRates = Set(supportedRemoteFrameRates(for: [format]))
            guard !frameRates.isEmpty else { continue }
            for colorMode in colorModes(for: format) {
                result[colorMode, default: []].formUnion(frameRates)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    private static func formatSupportsStabilization(_ format: AVCaptureDevice.Format) -> Bool {
        [
            AVCaptureVideoStabilizationMode.standard,
            .cinematic,
            .auto
        ].contains { format.isVideoStabilizationModeSupported($0) }
    }

    private static func formatSupportsCinematicVideoCapture(_ format: AVCaptureDevice.Format) -> Bool {
        if #available(iOS 26.0, *) {
            return format.isCinematicVideoCaptureSupported
        }
        return false
    }

    private static func supportedColorModes(from frameRates: [RemoteCameraColorMode: [Int]]) -> [RemoteCameraColorMode] {
        let modes = RemoteCameraColorMode.allCases.filter { mode in
            frameRates[mode]?.isEmpty == false
        }
        return modes.isEmpty ? [.standard] : modes
    }

    private static func colorModes(for format: AVCaptureDevice.Format) -> [RemoteCameraColorMode] {
        var modes: [RemoteCameraColorMode] = [.standard]
        if format.supportedColorSpaces.contains(.appleLog) {
            modes.append(.appleLog)
        }
        if #available(iOS 26.0, *), format.supportedColorSpaces.contains(.appleLog2) {
            modes.append(.appleLog2)
        }
        return modes
    }

    private static func format(_ format: AVCaptureDevice.Format, supports colorMode: RemoteCameraColorMode) -> Bool {
        colorModes(for: format).contains(colorMode)
    }

    private static let preferredFrameRates = [24, 25, 30, 60, 100, 120, 240]

    private static func hasMinimumProResStorageHeadroom() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = attributes[.systemFreeSize] as? NSNumber,
              let totalSize = attributes[.systemSize] as? NSNumber,
              totalSize.doubleValue > 0 else {
            return true
        }
        return freeSize.doubleValue / totalSize.doubleValue >= 0.10
    }

    private static func codecLabel(_ codec: AVVideoCodecType) -> String {
        switch codec {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .proRes422: return "ProRes 422"
        case .proRes4444: return "ProRes 4444"
        default: return codec.rawValue
        }
    }

    private static func preferredAutomaticCodec(from codecs: [AVVideoCodecType]) -> AVVideoCodecType? {
        if codecs.contains(.hevc) {
            return .hevc
        }
        return codecs.first
    }

    private static func formatID(for format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height)"
    }
}

private enum CameraCaptureError: LocalizedError {
    case sessionNotRunning
    case alreadyRecording
    case notRecording

    var errorDescription: String? {
        switch self {
        case .sessionNotRunning:
            "Camera session is not running."
        case .alreadyRecording:
            "Camera is already recording."
        case .notRecording:
            "Camera is not recording."
        }
    }
}

private final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<UInt64, Error>?
    private var startResult: Result<UInt64, Error>?
    private var didResolveStart = false
    var completion: (@Sendable (Result<URL, Error>) -> Void)?
    var unexpectedCompletion: (@Sendable (URL, Error?) -> Void)?
    var outputFileURL: URL?

    func waitForStart() async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let resolvedResult = startResult
            if resolvedResult == nil {
                startContinuation = continuation
            }
            lock.unlock()

            if let resolvedResult {
                switch resolvedResult {
                case .success(let startTime):
                    continuation.resume(returning: startTime)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        outputFileURL = fileURL
        resolveStart(.success(DispatchTime.now().uptimeNanoseconds))
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        self.outputFileURL = outputFileURL
        if let error {
            resolveStart(.failure(error))
        } else {
            resolveStart(.success(DispatchTime.now().uptimeNanoseconds))
        }
        guard let completion else {
            unexpectedCompletion?(outputFileURL, error)
            return
        }
        if let error {
            completion(.failure(error))
        } else {
            completion(.success(outputFileURL))
        }
    }

    private func resolveStart(_ result: Result<UInt64, Error>) {
        lock.lock()
        let continuation: CheckedContinuation<UInt64, Error>?
        if didResolveStart {
            continuation = nil
        } else {
            didResolveStart = true
            startResult = result
            continuation = startContinuation
            startContinuation = nil
        }
        lock.unlock()

        guard let continuation else { return }
        switch result {
        case .success(let startTime):
            continuation.resume(returning: startTime)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

struct CameraRecordingStartResult: Sendable {
    let url: URL
    let deviceStartTime: UInt64
}

struct CameraRecordingResult: Sendable {
    let url: URL
    let byteCount: Int64
    let durationSeconds: Double
    let stopReason: String?

    init(url: URL, stopReason: String? = nil) async throws {
        self.url = url
        self.stopReason = stopReason
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: url)
        durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
    }
}
