import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation
import OSLog

@MainActor
extension CameraCaptureController {
    private static let focusCandidatePublishIntervalSeconds: TimeInterval = 1.0 / 12.0
    private static let focusCandidateBoundsTolerance: CGFloat = 0.002

    private struct CinematicApertureRange {
        var minimum: Double
        var maximum: Double
        var `default`: Double
    }

    func configureCinematicSceneMonitoring(for device: AVCaptureDevice?) {
        cinematicSceneObservation?.invalidate()
        cinematicSceneObservation = nil
        setCinematicSceneWarning(nil)
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
        setCinematicSceneWarning(statuses.contains(.notEnoughLight) ? "Cinematic needs more light" : nil)
    }

    private func setCinematicSceneWarning(_ warning: String?) {
        guard cinematicSceneWarning != warning else { return }
        cinematicSceneWarning = warning
        publishCaptureWarningChanged()
    }

    func setCinematicFocusMetadataWarning(_ warning: String?) {
        guard cinematicFocusMetadataWarning != warning else { return }
        cinematicFocusMetadataWarning = warning
        publishCaptureWarningChanged()
    }

    func focusCinematic(at focusPoint: CameraPreviewFocusPoint, lockFocus: Bool) async -> Bool {
        guard activeCinematicVideoEnabled,
              activeDevice != nil else {
            return false
        }
        guard #available(iOS 26.0, *) else {
            return false
        }

        let metadataPoint = CGPoint(
            x: min(1, max(0, focusPoint.metadataPoint.x)),
            y: min(1, max(0, focusPoint.metadataPoint.y))
        )
        let candidate = latestCinematicFocusCandidates.first { $0.contains(metadataPoint) }
        let didApply = await configureActiveDevice { activeDevice in
            if lockFocus {
                activeDevice.setCinematicVideoFixedFocus(at: metadataPoint, focusMode: .strong)
            } else if let candidate {
                let focusMode: AVCaptureDevice.CinematicVideoFocusMode = candidate.focusMode == .weak
                    ? .strong
                    : .weak
                activeDevice.setCinematicVideoTrackingFocus(
                    detectedObjectID: candidate.objectID,
                    focusMode: focusMode
                )
            } else {
                activeDevice.setCinematicVideoTrackingFocus(at: metadataPoint, focusMode: .weak)
            }
        } == true
        if didApply {
            statusMessage = lockFocus ? "Cinematic focus locked" : "Cinematic focus set"
        } else {
            statusMessage = "Cinematic focus not available"
        }
        return didApply
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

    private func disableCinematicCapture(in settings: RemoteCameraSettings) -> RemoteCameraSettings {
        var disabledSettings = settings
        disabledSettings.cinematicVideoEnabled = false
        disabledSettings.cinematicAperture = nil
        activeCinematicVideoEnabled = false
        activeCinematicFocusMetadataEnabled = false
        activeCinematicAperture = nil
        setCinematicFocusMetadataWarning(nil)
        clearCinematicFocusCandidates()
        return disabledSettings
    }

    func applyCinematicSettings(_ settings: RemoteCameraSettings) async -> RemoteCameraSettings {
        var appliedSettings = settings
        guard let activeVideoInput else {
            return disableCinematicCapture(in: appliedSettings)
        }
        guard #available(iOS 26.0, *),
              activeVideoInput.isCinematicVideoCaptureSupported else {
            if appliedSettings.cinematicVideoEnabled {
                Self.logger.info("Cinematic requested but unsupported by active input")
            }
            return disableCinematicCapture(in: appliedSettings)
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
        let metadataOutput = metadataOutput
        let metadataDelegate = metadataDelegate
        let metadataQueue = metadataQueue
        let setMetadataOutputEnabled = { (isEnabled: Bool) -> Bool in
            Self.configureCinematicMetadataOutputIfNeeded(
                session: session,
                metadataOutput: metadataOutput,
                metadataDelegate: metadataDelegate,
                metadataQueue: metadataQueue,
                isEnabled: isEnabled
            )
        }
        let enabled = appliedSettings.cinematicVideoEnabled
        let aperture = appliedSettings.cinematicAperture
        if enabled == activeCinematicVideoEnabled,
           CameraCaptureSettingsPlanner.cinematicAperturesMatch(aperture, activeCinematicAperture) {
            return appliedSettings
        }
        guard !(await movieOutputIsRecording()) else {
            appliedSettings.cinematicVideoEnabled = activeCinematicVideoEnabled
            appliedSettings.cinematicAperture = activeCinematicAperture
            statusMessage = "Cinematic settings apply after recording stops"
            return appliedSettings
        }

        let appliedCinematicState = await runOnSessionQueue {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            activeVideoInput.isCinematicVideoCaptureEnabled = enabled
            if enabled, let aperture {
                activeVideoInput.simulatedAperture = Float(aperture)
            }
            let metadataEnabled = setMetadataOutputEnabled(enabled)
            let actualEnabled = activeVideoInput.isCinematicVideoCaptureEnabled
            let actualAperture = actualEnabled ? Double(activeVideoInput.simulatedAperture) : nil
            return (actualEnabled, actualAperture, metadataEnabled)
        }

        let retriedMetadataEnabled: Bool?
        if enabled && appliedCinematicState.0 && !appliedCinematicState.2 {
            retriedMetadataEnabled = await runOnSessionQueue {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                return setMetadataOutputEnabled(true)
            }
        } else {
            retriedMetadataEnabled = nil
        }

        let actualEnabled = enabled && appliedCinematicState.0
        let actualAperture = actualEnabled ? appliedCinematicState.1 : nil
        let actualMetadataEnabled = actualEnabled && (retriedMetadataEnabled ?? appliedCinematicState.2)
        if enabled && !actualEnabled {
            await runOnSessionQueue {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                _ = setMetadataOutputEnabled(false)
            }
        }
        activeCinematicVideoEnabled = actualEnabled
        activeCinematicFocusMetadataEnabled = actualMetadataEnabled
        activeCinematicAperture = actualAperture
        Self.logger.info(
            "Cinematic \(actualEnabled ? "enabled" : "disabled", privacy: .public), aperture \(actualAperture ?? -1, privacy: .public)"
        )
        if !actualEnabled {
            setCinematicFocusMetadataWarning(nil)
            setCinematicSceneWarning(nil)
            clearCinematicFocusCandidates()
        } else {
            setCinematicFocusMetadataWarning(
                actualMetadataEnabled ? nil : "Cinematic focus metadata unavailable"
            )
            publishCaptureWarningChanged()
        }
        appliedSettings.cinematicVideoEnabled = actualEnabled
        appliedSettings.cinematicAperture = actualAperture
        return appliedSettings
    }

    @discardableResult
    nonisolated static func configureCinematicMetadataOutputIfNeeded(
        session: AVCaptureSession,
        metadataOutput: AVCaptureMetadataOutput,
        metadataDelegate: AVCaptureMetadataOutputObjectsDelegate,
        metadataQueue: DispatchQueue,
        isEnabled: Bool
    ) -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        guard isEnabled else {
            metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
            if session.outputs.contains(metadataOutput) {
                session.removeOutput(metadataOutput)
            }
            return false
        }
        if !session.outputs.contains(metadataOutput), session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
        }
        guard session.outputs.contains(metadataOutput) else {
            metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
            return false
        }
        let requiredTypes = metadataOutput.requiredMetadataObjectTypesForCinematicVideoCapture
        let availableTypes = Set(metadataOutput.availableMetadataObjectTypes)
        guard !requiredTypes.isEmpty,
              requiredTypes.allSatisfy({ availableTypes.contains($0) }) else {
            metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
            session.removeOutput(metadataOutput)
            return false
        }
        metadataOutput.metadataObjectTypes = requiredTypes
        metadataOutput.setMetadataObjectsDelegate(metadataDelegate, queue: metadataQueue)
        return true
    }

    func clearCinematicFocusCandidates() {
        latestCinematicFocusCandidates = []
        cinematicFocusCandidates = []
        lastFocusCandidatePublishTime = 0
    }

    func updateCinematicFocusCandidates(_ candidates: [CameraCinematicFocusCandidate]) {
        latestCinematicFocusCandidates = candidates
        let now = ProcessInfo.processInfo.systemUptime
        let isMajorChange = Self.focusCandidateChangeIsMajor(cinematicFocusCandidates, candidates)
        let shouldPublish = isMajorChange
            || now - lastFocusCandidatePublishTime >= Self.focusCandidatePublishIntervalSeconds
        guard shouldPublish,
              !Self.focusCandidatesApproximatelyEqual(cinematicFocusCandidates, candidates) else {
            return
        }
        cinematicFocusCandidates = candidates
        lastFocusCandidatePublishTime = now
    }

    private static func focusCandidateChangeIsMajor(
        _ lhs: [CameraCinematicFocusCandidate],
        _ rhs: [CameraCinematicFocusCandidate]
    ) -> Bool {
        guard lhs.count == rhs.count else { return true }
        return focusCandidatesByID(lhs).mapValues(\.focusMode) != focusCandidatesByID(rhs).mapValues(\.focusMode)
    }

    private static func focusCandidatesApproximatelyEqual(
        _ lhs: [CameraCinematicFocusCandidate],
        _ rhs: [CameraCinematicFocusCandidate]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let lhsByID = focusCandidatesByID(lhs)
        for candidate in rhs {
            guard let other = lhsByID[candidate.objectID],
                  other.focusMode == candidate.focusMode,
                  abs(other.metadataBounds.origin.x - candidate.metadataBounds.origin.x) <= focusCandidateBoundsTolerance,
                  abs(other.metadataBounds.origin.y - candidate.metadataBounds.origin.y) <= focusCandidateBoundsTolerance,
                  abs(other.metadataBounds.width - candidate.metadataBounds.width) <= focusCandidateBoundsTolerance,
                  abs(other.metadataBounds.height - candidate.metadataBounds.height) <= focusCandidateBoundsTolerance else {
                return false
            }
        }
        return true
    }

    private static func focusCandidatesByID(
        _ candidates: [CameraCinematicFocusCandidate]
    ) -> [Int: CameraCinematicFocusCandidate] {
        var result: [Int: CameraCinematicFocusCandidate] = [:]
        result.reserveCapacity(candidates.count)
        for candidate in candidates {
            result[candidate.objectID] = candidate
        }
        return result
    }
}

final class CinematicMetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    var onCandidates: (@Sendable ([CameraCinematicFocusCandidate]) -> Void)?

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard #available(iOS 26.0, *) else {
            onCandidates?([])
            return
        }
        onCandidates?(metadataObjects.map { metadataObject in
            CameraCinematicFocusCandidate(
                objectID: metadataObject.objectID,
                metadataBounds: metadataObject.bounds,
                focusMode: CameraCinematicFocusMode(
                    rawValue: Int(metadataObject.cinematicVideoFocusMode.rawValue)
                ) ?? .none
            )
        })
    }
}
