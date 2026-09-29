import BlitzRecorderCore
import Foundation

extension RemoteCameraControlsPane {
    var deviceName: String {
        vm.selectedRemoteCameraCapabilities?.deviceName ?? "iPhone Camera"
    }

    var remoteCameraStatus: String {
        guard let telemetry = vm.selectedRemoteCameraTelemetry else {
            return "Waiting for iPhone"
        }
        if telemetry.phase == .transferring,
           let progress = telemetry.transferProgress {
            return "Transferring \(Int((progress.fraction * 100).rounded()))%"
        }
        if let previewHealth = telemetry.previewHealth,
           !previewHealth.isHealthy {
            if previewHealth.isTransferActive {
                return "Importing iPhone video"
            }
            if previewHealth.isStale {
                return "Live view stalled"
            }
            if previewHealth.isBlockedBeforeFirstFrame {
                return "Live view blocked"
            }
            if previewHealth.isDroppingFrames {
                return "iPhone live view is dropping frames"
            }
            if previewHealth.isWaitingForFirstFrame {
                return "Waiting for live view"
            }
            return "iPhone connected"
        }
        if let captureWarning = telemetry.captureWarning,
           !captureWarning.isEmpty {
            return captureWarning
        }
        return "\(telemetry.phase.rawValue.capitalized) - \(Int(telemetry.elapsedSeconds))s"
    }

    var allowsLiveCameraChanges: Bool {
        vm.state == .idle || vm.state == .recording
    }

    var allowsFormatChanges: Bool {
        vm.state == .idle
    }

    var cinematicLocksFormatControls: Bool {
        currentRemoteSettings.cinematicVideoEnabled
    }

    var currentRemoteSettings: RemoteCameraSettings {
        vm.selectedRemoteCameraTelemetry?.activeSettings ?? RemoteCameraSettings()
    }

    func currentFormatID(_ capabilities: RemoteCameraCapabilities) -> String {
        currentRemoteSettings.formatID ?? availableRemoteFormats(capabilities).first?.id ?? ""
    }

    func frameRates(for formatID: String, capabilities: RemoteCameraCapabilities) -> [Int] {
        let formats = availableRemoteFormats(capabilities)
        let format = formats.first(where: { $0.id == formatID }) ?? formats.first
        guard let format else { return [30] }
        return RemoteCameraSettingsResolver.compatibleFrameRates(
            for: format,
            profileID: currentRemoteSettings.captureProfileID,
            colorMode: currentRemoteSettings.colorMode,
            profiles: capabilities.supportedCaptureProfiles
        )
    }

    func availableColorModes(_ capabilities: RemoteCameraCapabilities) -> [RemoteCameraColorMode] {
        var formats = availableRemoteFormats(capabilities)
        if currentRemoteSettings.captureProfileID != .proRes422,
           let proResProfile = capabilities.supportedCaptureProfiles.first(where: { $0.id == .proRes422 && $0.isAvailable }),
           !proResProfile.supportedFormatIDs.isEmpty {
            let supportedIDs = Set(proResProfile.supportedFormatIDs)
            formats = capabilities.supportedFormats.filter { supportedIDs.contains($0.id) }
        }
        let modes = Set(formats.flatMap(\.colorModes))
        let ordered = RemoteCameraColorMode.allCases.filter { mode in
            mode == .standard || modes.contains(mode)
        }
        return ordered.isEmpty ? [.standard] : ordered
    }

    func availableRemoteFormats(_ capabilities: RemoteCameraCapabilities) -> [RemoteCameraFormat] {
        guard let profile = capabilities.supportedCaptureProfiles.first(where: { $0.id == currentRemoteSettings.captureProfileID }),
              !profile.supportedFormatIDs.isEmpty else {
            return capabilities.supportedFormats
        }
        let supportedIDs = Set(profile.supportedFormatIDs)
        var formats = capabilities.supportedFormats.filter { supportedIDs.contains($0.id) }
        if currentRemoteSettings.colorMode != .standard {
            let colorModeFormats = formats.filter { $0.colorModes.contains(currentRemoteSettings.colorMode) }
            if !colorModeFormats.isEmpty {
                formats = colorModeFormats
            }
        }
        return formats
    }

    func profileUnavailableReason(
        _ profileID: RemoteCameraCaptureProfileID,
        capabilities: RemoteCameraCapabilities
    ) -> String? {
        guard let profile = capabilities.supportedCaptureProfiles.first(where: { $0.id == profileID }),
              !profile.isAvailable else {
            return nil
        }
        switch profileID {
        case .automatic:
            return profile.unavailableReason ?? "Best is unavailable for this iPhone camera setting."
        case .highEfficiency:
            return profile.unavailableReason ?? "Small files are unavailable for this iPhone camera setting."
        case .proRes422:
            return profile.unavailableReason ?? "Pro means ProRes, and ProRes is unavailable for this iPhone camera setting."
        }
    }

    func cinematicUnavailableReason() -> String {
        var checks: [String] = []
        if currentRemoteSettings.captureProfileID == .proRes422 {
            checks.append("switch Recording to Best")
        }
        if currentRemoteSettings.lens != .wide {
            checks.append("switch Lens to Wide")
        }
        if currentRemoteSettings.frameRate != 30 {
            checks.append("switch FPS to 30")
        }
        if checks.isEmpty {
            return "Phone did not report Cinematic support. Reopen the latest iPhone app build and pair again."
        }
        return "Phone did not report Cinematic support. Try: \(checks.joined(separator: ", "))."
    }
}
