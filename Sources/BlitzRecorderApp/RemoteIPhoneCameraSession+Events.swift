import BlitzRecorderCore
import BlitzRecorderTransport
import CoreGraphics
import Foundation
import ImageIO

extension RemoteIPhoneCameraSession {
    func handle(_ event: RemoteCameraEvent) {
        let settings = readSettings()
        guard let serviceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) else {
            return
        }
        switch event {
        case .pairingChallenge(let challenge):
            sessionState.setConnectionState(.pairing, for: serviceID)
            if !challenge.requiresShortCode {
                controlClient.pair(shortCode: "", challenge: challenge)
                onMessage?("Verifying trusted Remote iPhone Camera...")
                onCameraConfigurationChanged?()
                return
            }
            guard let code = requestPairingCode(for: challenge) else {
                controlClient.send(.cancel)
                onMessage?("Remote iPhone pairing cancelled.")
                onCameraConfigurationChanged?()
                return
            }
            controlClient.pair(shortCode: code, challenge: challenge)
            onMessage?("Pairing \(challenge.deviceName)...")
            onCameraConfigurationChanged?()
        case .paired(let trust):
            var settings = readSettings()
            settings.trustedRemoteCameraServiceIDs.insert(serviceID)
            saveSettings(settings)
            sessionState.setConnectionState(.connected, for: serviceID)
            onMessage?("Paired \(trust.deviceName) as Remote iPhone Camera.")
            controlClient.send(.requestCapabilities)
            attemptPendingImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .capabilities(let capabilities):
            sessionState.setCapabilities(capabilities, for: serviceID)
            sessionState.setConnectionState(.connected, for: serviceID)
            onMessage?("Remote iPhone ready: \(capabilities.supportedLenses.map(\.displayName).joined(separator: ", "))")
            var settings = readSettings()
            if settings.selectedCameraID == RemoteCameraProviderID.make(for: serviceID),
               settings.selectedScenePreset?.supports(settings.layout) == true {
                refreshSelectedScenePresetLayoutIfNeeded(settings: &settings)
                saveSettings(settings)
            }
            if settings.remoteCameraSettingsByServiceID[serviceID] != nil,
               !sessionState.hasSentSettingsRestore(for: serviceID) {
                let restoredSettings = remoteSettings(for: serviceID)
                sessionState.updateTelemetrySettings(for: serviceID, activeSettings: restoredSettings)
                sessionState.markSettingsRestoreSent(for: serviceID)
                suppressPreview(serviceID: serviceID, message: "Updating iPhone camera...")
                controlClient.send(.applySettings(restoredSettings))
            }
            attemptPendingImports(serviceID: serviceID)
            onCameraConfigurationChanged?()
        case .telemetry(let telemetry):
            var settings = readSettings()
            let mergeResult = mergeAutomaticRotationTelemetry(
                telemetry,
                serviceID: serviceID,
                settings: &settings
            )
            sessionState.setTelemetry(mergeResult.telemetry, for: serviceID)
            if mergeResult.didUpdateSettings {
                saveSettings(settings)
            }
            onCameraConfigurationChanged?()
        case .failed(let failedTakeID, let reason):
            sessionState.setConnectionState(.degraded, for: serviceID)
            onMessage?("Remote iPhone error: \(reason)")
            runtime.handleFailed(takeID: failedTakeID, reason: reason)
        case .transferReady(let takeID, _, let byteCount, let manifest):
            runtime.applyTransferReady(
                takeID: takeID,
                byteCount: byteCount,
                manifest: manifest,
                settings: readSettings()
            )
            onCameraConfigurationChanged?()
        case .monitorFrame(let jpegData, _, _):
            guard !isPreviewSuppressed(serviceID: serviceID) else { return }
            if let image = Self.makeCGImage(fromJPEGData: jpegData) {
                onPreviewFrame?(image)
            }
        case .monitorVideoFrame(let frame):
            guard !isPreviewSuppressed(serviceID: serviceID) else { return }
            if let sampleBuffer = monitorSampleBufferFactory.makeSampleBuffer(from: frame) {
                onPreviewSampleBuffer?(sampleBuffer, frame.width, frame.height)
            }
        case .transferChunk(let takeID, let offset, let data, let isFinal):
            runtime.writeChunk(takeID: takeID, offset: offset, data: data, isFinal: isFinal)
            onCameraConfigurationChanged?()
        case .transferComplete(let takeID, let byteCount, let sha256):
            Task { @MainActor in
                await runtime.completeTransfer(
                    takeID: takeID,
                    byteCount: byteCount,
                    sha256: sha256,
                    settings: readSettings()
                )
                onCameraConfigurationChanged?()
            }
        case .prepared(let takeID, let deviceStartTime):
            runtime.resolvePrepared(takeID: takeID, deviceStartTime: deviceStartTime)
            onCameraConfigurationChanged?()
        case .started(let takeID, let deviceStartTime):
            runtime.resolveStarted(takeID: takeID, deviceStartTime: deviceStartTime)
            onCameraConfigurationChanged?()
        case .stopped(_, _, _, let reason):
            if let reason, !reason.isEmpty {
                onMessage?("Remote iPhone stopped recording: \(reason)")
            }
            onCameraConfigurationChanged?()
        }
    }

    private func attemptPendingImports(serviceID: String) {
        guard canAttemptPendingImports() else { return }
        runtime.requestPendingImports(serviceID: serviceID, settings: readSettings())
    }

    private func requestPairingCode(for challenge: RemoteCameraPairingChallenge) -> String? {
        guard let rawCode = onPairingCodeRequested?(challenge.deviceName) else {
            return nil
        }
        let code = RemoteCameraPairingCode.normalized(rawCode)
        return RemoteCameraPairingCode.isValid(code) ? code : nil
    }

    static func previewHealthStatus(_ health: RemoteCameraPreviewHealth) -> String {
        if health.isTransferActive {
            return "Importing iPhone video"
        }
        guard health.framesSent > 0 else {
            return "Waiting for live view"
        }
        if health.isStale {
            return "Live view stalled"
        }
        if health.isBlockedBeforeFirstFrame {
            return "Live view blocked"
        }
        if health.isDroppingFrames {
            return "iPhone live view is dropping frames"
        }
        return "iPhone connected"
    }

    private static func makeCGImage(fromJPEGData data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func iPhoneMarketingName(for identifier: String?) -> String? {
        guard let identifier else { return nil }
        return [
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max"
        ][identifier]
    }
}
