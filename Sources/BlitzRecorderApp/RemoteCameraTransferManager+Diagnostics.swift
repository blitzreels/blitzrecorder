import BlitzRecorderCore
import Foundation

extension RemoteCameraTransferManager {
    static func recordingDiagnosticsSummary(for manifest: RemoteCameraTransferManifest) -> String? {
        var messages: [String] = []
        let diagnostics = manifest.recordingDiagnostics

        if let expectedFormatID = manifest.settings.formatID,
           let captureFormatID = diagnostics?.captureFormatID,
           captureFormatID != expectedFormatID {
            messages.append("iPhone recorded \(captureFormatID), requested \(expectedFormatID).")
        }
        if let captureFrameRate = diagnostics?.captureFrameRate,
           manifest.settings.frameRate > 0,
           captureFrameRate > 0,
           captureFrameRate != manifest.settings.frameRate {
            messages.append("iPhone recorded \(captureFrameRate) fps, requested \(manifest.settings.frameRate) fps.")
        }
        if let captureColorMode = diagnostics?.captureColorMode,
           captureColorMode != manifest.settings.colorMode {
            messages.append(
                "iPhone recorded \(captureColorMode.displayName) color, requested \(manifest.settings.colorMode.displayName)."
            )
        }
        if let captureRotationDegrees = diagnostics?.captureRotationDegrees {
            let requestedRotationDegrees = RemoteCameraSettings.normalizedRotationDegrees(
                manifest.settings.rotationDegrees
            )
            if captureRotationDegrees != requestedRotationDegrees {
                messages.append(
                    "iPhone recorded \(captureRotationDegrees) degree rotation, requested \(requestedRotationDegrees) degrees."
                )
            }
        } else if diagnostics?.observedAtDeviceStartTime != nil {
            messages.append("Rotation was not reported by the iPhone recording.")
        }
        if manifest.settings.stabilizationMode != .off {
            if let captureStabilizationMode = diagnostics?.captureStabilizationMode {
                if !stabilizationMatches(
                    requested: manifest.settings.stabilizationMode,
                    captured: captureStabilizationMode
                ) {
                    messages.append(
                        "iPhone recorded \(captureStabilizationMode.displayName) stabilization, requested \(manifest.settings.stabilizationMode.displayName)."
                    )
                }
            } else if diagnostics?.observedAtDeviceStartTime != nil {
                messages.append("Stabilization mode was not reported by the iPhone recording.")
            }
        }

        if manifest.settings.cinematicVideoEnabled {
            switch diagnostics?.cinematicVideoCaptureEnabled {
            case .some(true):
                break
            case .some(false):
                messages.append("Cinematic was requested but was not active on the iPhone recording.")
            case .none:
                messages.append("Cinematic status was not reported by the iPhone recording.")
            }
            if manifest.format?.supportsCinematicVideo == false {
                messages.append("Recording format was not Cinematic-capable.")
            }
            if diagnostics?.cinematicVideoCaptureEnabled == true,
               diagnostics?.cinematicFocusMetadataEnabled == false {
                messages.append("Cinematic focus metadata was unavailable during recording.")
            }
            if diagnostics?.cinematicVideoCaptureEnabled == true,
               diagnostics?.cinematicAssetVerified == false {
                messages.append("The saved iPhone movie did not contain Cinematic depth metadata.")
            }
            if let codecLabel = manifest.captureCodecLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !codecLabel.isEmpty,
               !codecLabel.localizedCaseInsensitiveContains("HEVC") {
                messages.append(
                    "Cinematic recorded with \(codecLabel); HEVC is recommended for iPhone-quality Cinematic recordings."
                )
            }
            if diagnostics?.firstOrderAmbisonicsAudioSupported == true,
               diagnostics?.firstOrderAmbisonicsAudioEnabled != true {
                messages.append("Spatial audio was supported but not enabled for this Cinematic recording.")
            }

            if let requestedAperture = manifest.settings.cinematicAperture {
                if let recordedAperture = diagnostics?.simulatedAperture {
                    if abs(recordedAperture - requestedAperture) > 0.05 {
                        messages.append(
                            "Depth of field recorded at f/\(formattedAperture(recordedAperture)), requested f/\(formattedAperture(requestedAperture))."
                        )
                    }
                } else {
                    messages.append("Depth of field aperture was not reported by the iPhone recording.")
                }
            }
        }

        if diagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == false {
            messages.append("Orientation metadata was not recorded; rotation may need manual correction.")
        }

        if let captureWarning = diagnostics?.captureWarning, !captureWarning.isEmpty {
            messages.append(captureWarning)
        }

        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private static func stabilizationMatches(
        requested: RemoteCameraStabilizationMode,
        captured: RemoteCameraStabilizationMode
    ) -> Bool {
        switch requested {
        case .off:
            return captured == .off
        case .auto:
            return captured != .off
        case .standard:
            return captured == requested
        case .cinematic:
            return captured == .cinematic || captured == .cinematicExtendedEnhanced
        case .cinematicExtendedEnhanced:
            return captured == .cinematicExtendedEnhanced
        }
    }

    private static func formattedAperture(_ aperture: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: aperture)) ?? String(format: "%.1f", aperture)
    }
}
