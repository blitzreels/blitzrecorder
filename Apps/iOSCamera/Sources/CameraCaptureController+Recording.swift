import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation
import OSLog

@MainActor
extension CameraCaptureController {
    /// Pro Video Storage is only for ProRes; HEVC takes keep writing to the normal file location.
    nonisolated static func useProVideoStorageIfAvailable(_ movieOutput: AVCaptureMovieFileOutput) {
        guard #available(iOS 27.0, *) else { return }
        let codec = movieOutput.connection(with: .video).flatMap {
            movieOutput.outputSettings(for: $0)[AVVideoCodecKey] as? String
        }
        let isProRes = codec.map { $0.hasPrefix("ap") } ?? false
        let usesStorage = isProRes
            && movieOutput.isProVideoStorageSupported
            && AVProVideoStorage.shared?.busyReasons.isEmpty == true
        if movieOutput.usesProVideoStorage != usesStorage {
            movieOutput.usesProVideoStorage = usesStorage
        }
    }

    func startRecording(
        takeID: UUID,
        expectedSettings: RemoteCameraSettings
    ) async throws -> CameraRecordingStartResult {
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

        activeRecordingWarningAccumulator = RemoteCameraRecordingWarningAccumulator()
        setCaptureSessionWarning(nil)
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
        let activeVideoInput = activeVideoInput
        let activeAudioInput = activeAudioInput
        let activeDevice = activeDevice
        let activeCinematicFocusMetadataEnabled = activeCinematicFocusMetadataEnabled
        do {
            let recordingStart = try await runThrowingOnSessionQueue {
                guard session.isRunning else {
                    throw CameraCaptureError.sessionNotRunning
                }
                guard !movieOutput.isRecording else {
                    throw CameraCaptureError.alreadyRecording
                }
                if let activeDevice,
                   let pressureFailure = Self.recordingStartPressureFailure(for: activeDevice.systemPressureState) {
                    throw CameraCaptureError.cameraPressureTooHigh(pressureFailure)
                }
                if let settingsMismatch = Self.recordingStartSettingsMismatch(
                    expected: expectedSettings,
                    activeDevice: activeDevice
                ) {
                    throw CameraCaptureError.captureSettingsMismatch(settingsMismatch)
                }
                guard let videoConnection = movieOutput.connection(with: .video) else {
                    throw CameraCaptureError.videoConnectionUnavailable
                }
                let captureRotationDegrees = Self.rotationDegrees(for: videoConnection)
                if let rotationMismatch = Self.recordingStartRotationMismatch(
                    expected: expectedSettings.rotationDegrees,
                    actual: captureRotationDegrees
                ) {
                    throw CameraCaptureError.captureSettingsMismatch(rotationMismatch)
                }
                movieOutput.setRecordsVideoOrientationAndMirroringChangesAsMetadataTrack(
                    true,
                    for: videoConnection
                )
                let recordsOrientationMetadataTrack = movieOutput
                    .recordsVideoOrientationAndMirroringChangesAsMetadataTrack(for: videoConnection)
                let codecCheck = expectedSettings.cinematicVideoEnabled
                    ? Self.ensureHEVCCodecIfAvailable(movieOutput: movieOutput, connection: videoConnection)
                    : nil
                var cinematicVideoCaptureEnabled: Bool?
                var cinematicFocusMetadataEnabled: Bool?
                var simulatedAperture: Double?
                let captureFormatID = activeDevice.map {
                    RemoteCameraCaptureProfileResolver.formatID(for: $0.activeFormat)
                }
                let captureFrameRate = activeDevice.map(Self.activeFrameRate(for:)).flatMap { $0 > 0 ? $0 : nil }
                let captureColorMode = activeDevice.map(Self.activeColorMode(for:))
                if #available(iOS 26.0, *), let activeVideoInput {
                    cinematicVideoCaptureEnabled = activeVideoInput.isCinematicVideoCaptureEnabled
                    cinematicFocusMetadataEnabled = activeCinematicFocusMetadataEnabled
                    simulatedAperture = Double(activeVideoInput.simulatedAperture)
                }
                let firstOrderAmbisonicsAudioSupported = activeAudioInput?
                    .isMultichannelAudioModeSupported(.firstOrderAmbisonics)
                let firstOrderAmbisonicsAudioEnabled = activeAudioInput.map {
                    $0.multichannelAudioMode == .firstOrderAmbisonics
                }
                if expectedSettings.cinematicVideoEnabled {
                    guard cinematicVideoCaptureEnabled == true else {
                        throw CameraCaptureError.cinematicNotActive
                    }
                    guard let codecCheck, codecCheck.hevcWasAvailable else {
                        throw CameraCaptureError.cinematicHEVCUnavailable
                    }
                    if codecCheck.isHEVC != true {
                        throw CameraCaptureError.cinematicHEVCNotActive(actual: codecCheck.codecLabel)
                    }
                    if let expectedAperture = expectedSettings.cinematicAperture,
                       let simulatedAperture,
                       abs(simulatedAperture - expectedAperture) > 0.05 {
                        throw CameraCaptureError.cinematicApertureMismatch(
                            expected: expectedAperture,
                            actual: simulatedAperture
                        )
                    }
                }
                Self.useProVideoStorageIfAvailable(movieOutput)
                movieOutput.startRecording(to: url, recordingDelegate: delegate)
                return (RemoteCameraRecordingDiagnostics(
                    captureFormatID: captureFormatID,
                    captureFrameRate: captureFrameRate,
                    captureColorMode: captureColorMode,
                    captureStabilizationMode: nil,
                    captureRotationDegrees: captureRotationDegrees,
                    cinematicVideoCaptureEnabled: cinematicVideoCaptureEnabled,
                    cinematicFocusMetadataEnabled: cinematicFocusMetadataEnabled,
                    simulatedAperture: simulatedAperture,
                    recordsOrientationAndMirroringChangesAsMetadataTrack: recordsOrientationMetadataTrack,
                    firstOrderAmbisonicsAudioSupported: firstOrderAmbisonicsAudioSupported,
                    firstOrderAmbisonicsAudioEnabled: firstOrderAmbisonicsAudioEnabled
                ), codecCheck?.codecLabel)
            }
            let deviceStartTime = try await delegate.waitForStart()
            if let codecLabel = recordingStart.1 {
                activeCaptureCodecLabel = codecLabel
            }
            var observedDiagnostics = recordingStart.0
            observedDiagnostics.captureStabilizationMode = await runOnSessionQueue {
                movieOutput.connection(with: .video).map {
                    Self.remoteStabilizationMode(for: $0.activeVideoStabilizationMode)
                }
            }
            if let stabilizationMismatch = Self.recordingStartStabilizationMismatch(
                expected: expectedSettings.stabilizationMode,
                actual: observedDiagnostics.captureStabilizationMode
            ) {
                throw CameraCaptureError.captureSettingsMismatch(stabilizationMismatch)
            }
            activeRecordingWarningAccumulator.record(captureWarning)
            observedDiagnostics.captureWarning = activeRecordingWarningAccumulator.captureWarning
            observedDiagnostics.observedAtDeviceStartTime = deviceStartTime
            activeRecordingDiagnostics = observedDiagnostics
            Self.logger.info("Movie recording started for take \(takeID.uuidString, privacy: .public)")
            isRecording = true
            statusMessage = "Recording"
            return CameraRecordingStartResult(
                url: url,
                deviceStartTime: deviceStartTime,
                diagnostics: observedDiagnostics
            )
        } catch {
            Self.logger.error("Movie recording failed to start for take \(takeID.uuidString, privacy: .public): \(String(describing: error as NSError), privacy: .public)")
            delegate.unexpectedCompletion = nil
            delegate.completion = { _ in
                try? FileManager.default.removeItem(at: url)
            }
            let didRequestStop = await runOnSessionQueue {
                guard movieOutput.isRecording else { return false }
                movieOutput.stopRecording()
                return true
            }
            if !didRequestStop {
                try? FileManager.default.removeItem(at: url)
            }
            recordingDelegate = nil
            activeRecordingURL = nil
            activeRecordingDiagnostics = nil
            activeRecordingWarningAccumulator = RemoteCameraRecordingWarningAccumulator()
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

    func stopRecording() async throws -> CameraRecordingResult {
        let movieOutput = movieOutput
        guard await movieOutputIsRecording() else {
            guard let activeRecordingURL else {
                throw CameraCaptureError.notRecording
            }
            isRecording = false
            recordingDelegate = nil
            let diagnostics = consumeRecordingResultDiagnostics()
            self.activeRecordingURL = nil
            return try await CameraRecordingResult(
                url: activeRecordingURL,
                recordingDiagnostics: diagnostics
            )
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
                    let diagnostics = self.consumeRecordingResultDiagnostics()
                    switch result {
                    case .success(let url):
                        do {
                            continuation.resume(returning: try await CameraRecordingResult(
                                url: url,
                                recordingDiagnostics: diagnostics
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        if let url = finishedURL,
                           self.recordingLibrary.hasRecoverableMedia(at: url) {
                            do {
                                continuation.resume(returning: try await CameraRecordingResult(
                                    url: url,
                                    stopReason: error.localizedDescription,
                                    recordingDiagnostics: diagnostics
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
        let diagnostics = consumeRecordingResultDiagnostics()
        let result: Result<CameraRecordingResult, Error>
        if recordingLibrary.hasRecoverableMedia(at: url) {
            do {
                result = .success(try await CameraRecordingResult(
                    url: url,
                    stopReason: error?.localizedDescription,
                    recordingDiagnostics: diagnostics
                ))
            } catch {
                result = .failure(error)
            }
        } else if let error {
            result = .failure(error)
        } else {
            result = .failure(CameraCaptureError.notRecording)
        }
        // A stop that arrived meanwhile already took this clip.
        guard activeRecordingURL == url else { return }
        activeRecordingURL = nil
        onRecordingFinishedUnexpectedly?(result)
    }

    private func consumeRecordingResultDiagnostics() -> RemoteCameraRecordingDiagnostics? {
        defer {
            activeRecordingDiagnostics = nil
            activeRecordingWarningAccumulator = RemoteCameraRecordingWarningAccumulator()
        }
        var diagnostics = activeRecordingDiagnostics
        if let captureWarning = activeRecordingWarningAccumulator.recordingWarning(including: captureWarning) {
            if diagnostics == nil {
                diagnostics = RemoteCameraRecordingDiagnostics()
            }
            diagnostics?.captureWarning = captureWarning
        }
        return diagnostics
    }

    private nonisolated static func recordingStartPressureFailure(
        for state: AVCaptureDevice.SystemPressureState
    ) -> String? {
        switch state.level {
        case .critical:
            return "iPhone is too hot to start a reliable recording."
        case .shutdown:
            return "iPhone camera is stopped due to heat."
        default:
            return nil
        }
    }

    private nonisolated static func recordingStartSettingsMismatch(
        expected: RemoteCameraSettings,
        activeDevice: AVCaptureDevice?
    ) -> String? {
        guard let activeDevice else {
            return "iPhone camera is not configured."
        }
        if let expectedFormatID = expected.formatID {
            let actualFormatID = RemoteCameraCaptureProfileResolver.formatID(for: activeDevice.activeFormat)
            if actualFormatID != expectedFormatID {
                return "iPhone camera is on \(actualFormatID), not \(expectedFormatID)."
            }
        }
        let actualFrameRate = activeFrameRate(for: activeDevice)
        if expected.frameRate > 0, actualFrameRate > 0, actualFrameRate != expected.frameRate {
            return "iPhone camera is at \(actualFrameRate) fps, not \(expected.frameRate) fps."
        }
        let actualColorMode = activeColorMode(for: activeDevice)
        if actualColorMode != expected.colorMode {
            return "iPhone camera color is \(actualColorMode.displayName), not \(expected.colorMode.displayName)."
        }
        if expected.cinematicVideoEnabled {
            if #available(iOS 26.0, *) {
                if !activeDevice.activeFormat.isCinematicVideoCaptureSupported {
                    return "Selected iPhone camera format does not support Cinematic."
                }
            } else {
                return "Cinematic needs iOS 26 or later."
            }
        }
        return nil
    }

    private nonisolated static func recordingStartStabilizationMismatch(
        expected: RemoteCameraStabilizationMode,
        actual: RemoteCameraStabilizationMode?
    ) -> String? {
        guard expected != .off else { return nil }
        guard let actual else {
            return "iPhone camera stabilization mode was not reported."
        }
        guard stabilizationMatches(requested: expected, captured: actual) else {
            return "iPhone camera stabilization is \(actual.displayName), not \(expected.displayName)."
        }
        return nil
    }

    private nonisolated static func recordingStartRotationMismatch(
        expected: Int,
        actual: Int?
    ) -> String? {
        guard let actual else {
            return "iPhone camera rotation was not reported."
        }
        let expected = RemoteCameraSettings.normalizedRotationDegrees(expected)
        guard actual != expected else { return nil }
        return "iPhone camera rotation is \(actual) degrees, not \(expected) degrees."
    }

    private static func ensureHEVCCodecIfAvailable(
        movieOutput: AVCaptureMovieFileOutput,
        connection: AVCaptureConnection
    ) -> (hevcWasAvailable: Bool, isHEVC: Bool?, codecLabel: String?) {
        let hevcWasAvailable = movieOutput.availableVideoCodecTypes.contains(.hevc)
        if hevcWasAvailable {
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc.rawValue], for: connection)
        }

        let codec = outputCodec(movieOutput: movieOutput, connection: connection)
        return (
            hevcWasAvailable,
            codec.map { $0 == .hevc },
            codec.map(RemoteCameraCaptureProfileResolver.codecLabel)
        )
    }

    private static func outputCodec(
        movieOutput: AVCaptureMovieFileOutput,
        connection: AVCaptureConnection
    ) -> AVVideoCodecType? {
        let outputSettings = movieOutput.outputSettings(for: connection)
        if let codec = outputSettings[AVVideoCodecKey] as? AVVideoCodecType {
            return codec
        }
        if let rawCodec = outputSettings[AVVideoCodecKey] as? String {
            return AVVideoCodecType(rawValue: rawCodec)
        }
        return nil
    }
}
