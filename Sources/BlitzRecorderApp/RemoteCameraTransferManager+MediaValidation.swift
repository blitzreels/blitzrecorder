import BlitzRecorderCore
import AVFoundation
import CoreMedia
#if canImport(Cinematic)
import Cinematic
#endif
import Foundation

extension RemoteCameraTransferManager {
    static func validateImportedMedia(
        url: URL,
        manifest: RemoteCameraTransferManifest?
    ) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw RecorderError.remoteCameraTransferFailed("Imported iPhone recording has no video track.")
        }

        let durationSeconds = try await asset.load(.duration).seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw RecorderError.remoteCameraTransferFailed("Imported iPhone recording has an invalid duration.")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            throw RecorderError.remoteCameraTransferFailed("Imported iPhone recording has invalid video dimensions.")
        }

        if let expectedDuration = manifest?.durationSeconds,
           expectedDuration.isFinite,
           expectedDuration > 0 {
            let tolerance = max(0.75, expectedDuration * 0.05)
            guard abs(durationSeconds - expectedDuration) <= tolerance else {
                throw RecorderError.remoteCameraTransferFailed(
                    "Imported iPhone recording duration mismatch. Expected \(formattedSeconds(expectedDuration)), got \(formattedSeconds(durationSeconds))."
                )
            }
        }

        var warnings: [String] = []
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.format?.supportsCinematicVideo == false {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording manifest says Cinematic was requested, but the recording format was not Cinematic-capable."
            )
        }
        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        if manifest?.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == true,
           metadataTracks.isEmpty {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording is missing the orientation metadata track needed for WYSIWYG rotation."
            )
        }
        if manifest?.recordingDiagnostics?.recordsOrientationAndMirroringChangesAsMetadataTrack == false,
           manifest?.settings.usesAutomaticRotation == true {
            throw RecorderError.remoteCameraTransferFailed(
                "Automatic iPhone rotation was enabled, but the recording did not include orientation metadata."
            )
        }
        if let requestedRotationDegrees = manifest?.settings.rotationDegrees,
           let captureRotationDegrees = manifest?.recordingDiagnostics?.captureRotationDegrees,
           RemoteCameraSettings.normalizedRotationDegrees(requestedRotationDegrees)
                != RemoteCameraSettings.normalizedRotationDegrees(captureRotationDegrees) {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording rotation mismatch. Expected \(RemoteCameraSettings.normalizedRotationDegrees(requestedRotationDegrees)) degrees, got \(RemoteCameraSettings.normalizedRotationDegrees(captureRotationDegrees)) degrees."
            )
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled != true {
            warnings.append("Cinematic was requested but the imported manifest does not prove it was active")
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true,
           manifest?.recordingDiagnostics?.cinematicAssetVerified == false {
            throw RecorderError.remoteCameraTransferFailed(
                "The iPhone saved this take without Cinematic depth metadata."
            )
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           let codecLabel = try await videoCodecLabel(for: videoTrack),
           !codecLabel.localizedCaseInsensitiveContains("HEVC") {
            let message = "Cinematic recording used \(codecLabel); HEVC is required for iPhone-quality Cinematic recordings"
            if manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true {
                throw RecorderError.remoteCameraTransferFailed(message)
            }
            warnings.append(message)
        }
        if manifest?.settings.cinematicVideoEnabled == true,
           manifest?.recordingDiagnostics?.cinematicVideoCaptureEnabled == true {
            try await validateImportedCinematicAsset(asset)
        }
        return warnings
    }

    private static func validateImportedCinematicAsset(_ asset: AVAsset) async throws {
        #if canImport(Cinematic)
        guard await CNAssetInfo.isCinematic(asset: asset) else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording is not a Cinematic asset; depth metadata was lost."
            )
        }

        let assetInfo = try await CNAssetInfo(asset: asset)
        guard !assetInfo.allCinematicTracks.isEmpty else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording has no Cinematic tracks."
            )
        }
        let requiredTrackIDs = [
            assetInfo.cinematicVideoTrack.trackID,
            assetInfo.cinematicDisparityTrack.trackID,
            assetInfo.cinematicMetadataTrack.trackID
        ]
        guard requiredTrackIDs.allSatisfy({ $0 != 0 }) else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording is missing a Cinematic video, disparity, or metadata track."
            )
        }

        let cinematicDuration = assetInfo.timeRange.duration.seconds
        guard cinematicDuration.isFinite, cinematicDuration > 0 else {
            throw RecorderError.remoteCameraTransferFailed(
                "Imported iPhone recording has invalid Cinematic timing metadata."
            )
        }
        #else
        throw RecorderError.remoteCameraTransferFailed(
            "This Mac build cannot validate Cinematic iPhone recordings because the Cinematic framework is unavailable."
        )
        #endif
    }

    private static func videoCodecLabel(for videoTrack: AVAssetTrack) async throws -> String? {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            return nil
        }
        return videoCodecLabel(for: CMFormatDescriptionGetMediaSubType(formatDescription))
    }

    private static func videoCodecLabel(for codec: FourCharCode) -> String {
        switch codec {
        case kCMVideoCodecType_HEVC:
            return "HEVC"
        case kCMVideoCodecType_H264:
            return "H.264"
        case kCMVideoCodecType_AppleProRes422:
            return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444:
            return "ProRes 4444"
        default:
            return fourCharacterCode(codec)
        }
    }

    private static func fourCharacterCode(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let scalars = bytes.map { byte -> UnicodeScalar in
            let scalar = byte >= 32 && byte <= 126 ? byte : UInt8(ascii: "?")
            return UnicodeScalar(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func formattedSeconds(_ seconds: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: NSNumber(value: seconds)) ?? String(format: "%.2f", seconds)
    }
}
