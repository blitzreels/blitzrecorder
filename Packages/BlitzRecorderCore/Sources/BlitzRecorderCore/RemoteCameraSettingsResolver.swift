import Foundation

public enum RemoteCameraSettingsResolver {
    public static func normalized(
        _ proposedSettings: RemoteCameraSettings,
        capabilities: RemoteCameraCapabilities?,
        preferredFrameRate: Int
    ) -> RemoteCameraSettings {
        var remoteSettings = proposedSettings
        let supportedLenses = capabilities?.supportedLenses ?? []
        remoteSettings.lens = supportedLenses.contains(remoteSettings.lens)
            ? remoteSettings.lens
            : (supportedLenses.first ?? .wide)
        let lensCapabilities = capabilities?.capabilities(for: remoteSettings.lens) ?? capabilities
        let supportedProfiles = lensCapabilities?.supportedCaptureProfiles ?? [
            RemoteCameraCaptureProfile(id: .automatic)
        ]
        if !supportedProfiles.contains(where: { $0.id == remoteSettings.captureProfileID && $0.isAvailable }) {
            remoteSettings.captureProfileID = .automatic
        }
        let isCinematicRequested = remoteSettings.cinematicVideoEnabled
            && lensCapabilities?.supportsCinematicVideo == true
        if isCinematicRequested {
            remoteSettings.captureProfileID = preferredCinematicCaptureProfile(from: supportedProfiles)
            remoteSettings.colorMode = .standard
        }
        if remoteSettings.colorMode != .standard,
           let proResProfile = supportedProfiles.first(where: { $0.id == .proRes422 && $0.isAvailable }) {
            remoteSettings.captureProfileID = proResProfile.id
        } else if remoteSettings.colorMode != .standard {
            remoteSettings.colorMode = .standard
        }
        let selectableFormats = formats(
            lensCapabilities?.supportedFormats ?? [],
            supportedBy: remoteSettings.captureProfileID,
            profiles: supportedProfiles
        )
        let formatCandidates = selectableFormats.isEmpty ? (lensCapabilities?.supportedFormats ?? []) : selectableFormats
        let colorModeFormatCandidates: [RemoteCameraFormat]
        if remoteSettings.colorMode == .standard {
            colorModeFormatCandidates = formatCandidates
        } else {
            let matchingFormats = formatCandidates.filter { $0.colorModes.contains(remoteSettings.colorMode) }
            colorModeFormatCandidates = matchingFormats.isEmpty ? formatCandidates : matchingFormats
        }
        let hasKnownCinematicFormats = formatCandidates.contains(where: \.supportsCinematicVideo)
        let effectiveFormatCandidates = isCinematicRequested && hasKnownCinematicFormats
            ? colorModeFormatCandidates.filter(\.supportsCinematicVideo)
            : colorModeFormatCandidates
        let format = effectiveFormatCandidates.first { format in
            format.id == remoteSettings.formatID && format.frameRates.contains(remoteSettings.frameRate)
        } ?? effectiveFormatCandidates.first { format in
            format.frameRates.contains(preferredFrameRate)
        } ?? effectiveFormatCandidates.first
        remoteSettings.formatID = format?.id
        if let format, !format.colorModes.contains(remoteSettings.colorMode) {
            remoteSettings.colorMode = .standard
        }
        let frameRates = format.map {
            compatibleFrameRates(
                for: $0,
                profileID: remoteSettings.captureProfileID,
                colorMode: remoteSettings.colorMode,
                profiles: supportedProfiles
            )
        } ?? []
        remoteSettings.frameRate = frameRates.contains(remoteSettings.frameRate) == true
            ? remoteSettings.frameRate
            : (frameRates.contains(preferredFrameRate) == true
                ? preferredFrameRate
                : (frameRates.first ?? preferredFrameRate))
        remoteSettings.zoomFactor = 1
        remoteSettings.torchEnabled = false
        remoteSettings.focusPosition = min(1, max(0, remoteSettings.focusPosition))
        if let lensCapabilities {
            normalizeFeatureSettings(&remoteSettings, capabilities: lensCapabilities)
        }
        remoteSettings.rotationDegrees = RemoteCameraSettings.normalizedRotationDegrees(remoteSettings.rotationDegrees)
        return remoteSettings
    }

    public static func formats(
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

    public static func compatibleFrameRates(
        for format: RemoteCameraFormat,
        profileID: RemoteCameraCaptureProfileID,
        colorMode: RemoteCameraColorMode,
        profiles: [RemoteCameraCaptureProfile]
    ) -> [Int] {
        var frameRates = Set(format.frameRates)
        if let profile = profiles.first(where: { $0.id == profileID }),
           let profileFrameRates = profile.supportedFormatFrameRates[format.id],
           !profileFrameRates.isEmpty {
            frameRates.formIntersection(profileFrameRates)
        }
        if colorMode != .standard,
           let colorModeFrameRates = format.colorModeFrameRates[colorMode],
           !colorModeFrameRates.isEmpty {
            frameRates.formIntersection(colorModeFrameRates)
        }
        let sortedFrameRates = frameRates.sorted()
        return sortedFrameRates.isEmpty ? format.frameRates : sortedFrameRates
    }

    public static func aspectRatio(width: Int, height: Int, rotationDegrees: Int) -> Double {
        let width = Double(max(1, width))
        let height = Double(max(1, height))
        let landscapeAspectRatio = max(width, height) / min(width, height)
        if isPortraitRotation(rotationDegrees) {
            return 1 / landscapeAspectRatio
        }
        return landscapeAspectRatio
    }

    public static func aspectRatio(format: RemoteCameraFormat, rotationDegrees: Int) -> Double {
        aspectRatio(width: format.width, height: format.height, rotationDegrees: rotationDegrees)
    }

    public static func preferredCinematicCaptureProfile(
        from profiles: [RemoteCameraCaptureProfile]
    ) -> RemoteCameraCaptureProfileID {
        if profiles.contains(where: { $0.id == .highEfficiency && $0.isAvailable }) {
            return .highEfficiency
        }
        return .automatic
    }

    public static func isPortraitRotation(_ rotationDegrees: Int) -> Bool {
        switch RemoteCameraSettings.normalizedRotationDegrees(rotationDegrees) {
        case 0, 180:
            return true
        default:
            return false
        }
    }

    private static func normalizeFeatureSettings(
        _ remoteSettings: inout RemoteCameraSettings,
        capabilities: RemoteCameraCapabilities
    ) {
        if !capabilities.supportsCinematicVideo {
            remoteSettings.cinematicVideoEnabled = false
            remoteSettings.cinematicAperture = nil
        } else if remoteSettings.cinematicVideoEnabled {
            remoteSettings.focusMode = .continuousAuto
            if let minimumAperture = capabilities.minimumCinematicAperture,
               let maximumAperture = capabilities.maximumCinematicAperture {
                let proposedAperture = remoteSettings.cinematicAperture
                    ?? capabilities.defaultCinematicAperture
                    ?? minimumAperture
                remoteSettings.cinematicAperture = min(maximumAperture, max(minimumAperture, proposedAperture))
            } else {
                remoteSettings.cinematicAperture = nil
            }
        } else {
            remoteSettings.cinematicAperture = nil
        }
        if remoteSettings.focusMode == .locked, !capabilities.supportsFocusLock {
            remoteSettings.focusMode = .continuousAuto
        }
        if remoteSettings.focusMode == .manual, !capabilities.supportsManualFocus {
            remoteSettings.focusMode = .continuousAuto
        }
        if remoteSettings.exposureMode == .locked, !capabilities.supportsExposureLock {
            remoteSettings.exposureMode = .continuousAuto
        }
        if remoteSettings.exposureMode == .manual, !capabilities.supportsManualExposure {
            remoteSettings.exposureMode = .continuousAuto
            remoteSettings.iso = nil
            remoteSettings.shutterDurationSeconds = nil
        }
        if remoteSettings.whiteBalanceMode == .locked, !capabilities.supportsWhiteBalanceLock {
            remoteSettings.whiteBalanceMode = .continuousAuto
        }
        if remoteSettings.whiteBalanceMode == .manual, !capabilities.supportsManualWhiteBalance {
            remoteSettings.whiteBalanceMode = .continuousAuto
        }
        if remoteSettings.exposureMode == .continuousAuto {
            remoteSettings.exposureBias = 0
        } else if capabilities.minimumExposureBias < capabilities.maximumExposureBias {
            remoteSettings.exposureBias = min(
                capabilities.maximumExposureBias,
                max(capabilities.minimumExposureBias, remoteSettings.exposureBias)
            )
        }
        if let minimumISO = capabilities.minimumISO,
           let maximumISO = capabilities.maximumISO,
           let iso = remoteSettings.iso {
            remoteSettings.iso = min(maximumISO, max(minimumISO, iso))
        }
        if let minimumShutter = capabilities.minimumShutterDurationSeconds,
           let maximumShutter = capabilities.maximumShutterDurationSeconds,
           let shutterDuration = remoteSettings.shutterDurationSeconds {
            remoteSettings.shutterDurationSeconds = min(maximumShutter, max(minimumShutter, shutterDuration))
        }
        if !capabilities.supportedStabilizationModes.contains(remoteSettings.stabilizationMode) {
            remoteSettings.stabilizationMode = capabilities.supportedStabilizationModes.first ?? .off
        }
        let requestedRotation = RemoteCameraSettings.normalizedRotationDegrees(remoteSettings.rotationDegrees)
        if capabilities.supportedRotationDegrees.contains(requestedRotation) {
            remoteSettings.rotationDegrees = requestedRotation
        } else {
            remoteSettings.rotationDegrees = capabilities.supportedRotationDegrees.first ?? 0
        }
    }
}
