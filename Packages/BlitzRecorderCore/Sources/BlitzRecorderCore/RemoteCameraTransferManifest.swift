import Foundation

public struct RemoteCameraRecordingDiagnostics: Codable, Equatable, Sendable {
    public var captureFormatID: String?
    public var captureFrameRate: Int?
    public var captureColorMode: RemoteCameraColorMode?
    public var captureStabilizationMode: RemoteCameraStabilizationMode?
    public var captureRotationDegrees: Int?
    public var cinematicVideoCaptureEnabled: Bool?
    public var cinematicFocusMetadataEnabled: Bool?
    public var simulatedAperture: Double?
    public var recordsOrientationAndMirroringChangesAsMetadataTrack: Bool?
    public var recordedVideoCodecTypes: [String]?
    public var recordedMetadataTrackCount: Int?
    public var cinematicAssetVerified: Bool?
    public var cinematicTrackCount: Int?
    public var cinematicDurationSeconds: Double?
    public var firstOrderAmbisonicsAudioSupported: Bool?
    public var firstOrderAmbisonicsAudioEnabled: Bool?
    public var captureWarning: String?
    public var observedAtDeviceStartTime: UInt64?

    public init(
        captureFormatID: String? = nil,
        captureFrameRate: Int? = nil,
        captureColorMode: RemoteCameraColorMode? = nil,
        captureStabilizationMode: RemoteCameraStabilizationMode? = nil,
        captureRotationDegrees: Int? = nil,
        cinematicVideoCaptureEnabled: Bool? = nil,
        cinematicFocusMetadataEnabled: Bool? = nil,
        simulatedAperture: Double? = nil,
        recordsOrientationAndMirroringChangesAsMetadataTrack: Bool? = nil,
        recordedVideoCodecTypes: [String]? = nil,
        recordedMetadataTrackCount: Int? = nil,
        cinematicAssetVerified: Bool? = nil,
        cinematicTrackCount: Int? = nil,
        cinematicDurationSeconds: Double? = nil,
        firstOrderAmbisonicsAudioSupported: Bool? = nil,
        firstOrderAmbisonicsAudioEnabled: Bool? = nil,
        captureWarning: String? = nil,
        observedAtDeviceStartTime: UInt64? = nil
    ) {
        self.captureFormatID = captureFormatID
        self.captureFrameRate = captureFrameRate
        self.captureColorMode = captureColorMode
        self.captureStabilizationMode = captureStabilizationMode
        self.captureRotationDegrees = captureRotationDegrees.map(RemoteCameraSettings.normalizedRotationDegrees)
        self.cinematicVideoCaptureEnabled = cinematicVideoCaptureEnabled
        self.cinematicFocusMetadataEnabled = cinematicFocusMetadataEnabled
        self.simulatedAperture = simulatedAperture
        self.recordsOrientationAndMirroringChangesAsMetadataTrack = recordsOrientationAndMirroringChangesAsMetadataTrack
        self.recordedVideoCodecTypes = recordedVideoCodecTypes
        self.recordedMetadataTrackCount = recordedMetadataTrackCount
        self.cinematicAssetVerified = cinematicAssetVerified
        self.cinematicTrackCount = cinematicTrackCount
        self.cinematicDurationSeconds = cinematicDurationSeconds
        self.firstOrderAmbisonicsAudioSupported = firstOrderAmbisonicsAudioSupported
        self.firstOrderAmbisonicsAudioEnabled = firstOrderAmbisonicsAudioEnabled
        self.captureWarning = captureWarning
        self.observedAtDeviceStartTime = observedAtDeviceStartTime
    }

    public func merging(_ update: RemoteCameraRecordingDiagnostics?) -> RemoteCameraRecordingDiagnostics {
        guard let update else { return self }
        var merged = self
        if let value = update.captureFormatID {
            merged.captureFormatID = value
        }
        if let value = update.captureFrameRate {
            merged.captureFrameRate = value
        }
        if let value = update.captureColorMode {
            merged.captureColorMode = value
        }
        if let value = update.captureStabilizationMode {
            merged.captureStabilizationMode = value
        }
        if let value = update.captureRotationDegrees {
            merged.captureRotationDegrees = value
        }
        if let value = update.cinematicVideoCaptureEnabled {
            merged.cinematicVideoCaptureEnabled = value
        }
        if let value = update.cinematicFocusMetadataEnabled {
            merged.cinematicFocusMetadataEnabled = value
        }
        if let value = update.simulatedAperture {
            merged.simulatedAperture = value
        }
        if let value = update.recordsOrientationAndMirroringChangesAsMetadataTrack {
            merged.recordsOrientationAndMirroringChangesAsMetadataTrack = value
        }
        if let value = update.recordedVideoCodecTypes {
            merged.recordedVideoCodecTypes = value
        }
        if let value = update.recordedMetadataTrackCount {
            merged.recordedMetadataTrackCount = value
        }
        if let value = update.cinematicAssetVerified {
            merged.cinematicAssetVerified = value
        }
        if let value = update.cinematicTrackCount {
            merged.cinematicTrackCount = value
        }
        if let value = update.cinematicDurationSeconds {
            merged.cinematicDurationSeconds = value
        }
        if let value = update.firstOrderAmbisonicsAudioSupported {
            merged.firstOrderAmbisonicsAudioSupported = value
        }
        if let value = update.firstOrderAmbisonicsAudioEnabled {
            merged.firstOrderAmbisonicsAudioEnabled = value
        }
        merged.captureWarning = RemoteCameraRecordingWarningAccumulator.mergedWarning(
            merged.captureWarning,
            update.captureWarning
        )
        if let value = update.observedAtDeviceStartTime {
            merged.observedAtDeviceStartTime = value
        }
        return merged
    }
}

public struct RemoteCameraRecordingWarningAccumulator: Equatable, Sendable {
    private var warnings: [String]

    public init(warnings: [String] = []) {
        self.warnings = []
        warnings.forEach { record($0) }
    }

    public mutating func record(_ warning: String?) {
        guard let warning = Self.normalizedWarning(warning),
              !warnings.contains(warning) else {
            return
        }
        warnings.append(warning)
    }

    public mutating func recordingWarning(including currentWarning: String?) -> String? {
        record(currentWarning)
        return captureWarning
    }

    public var captureWarning: String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.joined(separator: ". ")
    }

    public static func mergedWarning(_ existingWarning: String?, _ updateWarning: String?) -> String? {
        guard let existing = normalizedWarning(existingWarning) else {
            return normalizedWarning(updateWarning)
        }
        guard let update = normalizedWarning(updateWarning) else {
            return existing
        }
        if existing == update || existing.contains(update) {
            return existing
        }
        return [existing, update].joined(separator: ". ")
    }

    private static func normalizedWarning(_ warning: String?) -> String? {
        guard let warning else { return nil }
        let normalized = warning.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

public struct RemoteCameraTransferManifest: Codable, Equatable, Sendable {
    public var takeID: UUID
    public var recordingID: UUID
    public var fileName: String
    public var byteCount: Int64
    public var sha256: String?
    public var durationSeconds: Double
    public var resumeOffset: Int64
    public var settings: RemoteCameraSettings
    public var format: RemoteCameraFormat?
    public var captureProfileID: RemoteCameraCaptureProfileID
    public var captureCodecLabel: String?
    public var captureFormatLabel: String?
    public var deviceStartTime: UInt64?
    public var deviceStopTime: UInt64?
    public var hostStartTime: UInt64?
    public var hostStopTime: UInt64?
    public var hostTimelineStartTime: UInt64?
    public var estimatedHostStartTime: UInt64?
    public var stopReason: String?
    public var recordingDiagnostics: RemoteCameraRecordingDiagnostics?

    public init(
        takeID: UUID,
        recordingID: UUID,
        fileName: String,
        byteCount: Int64,
        sha256: String? = nil,
        durationSeconds: Double,
        resumeOffset: Int64 = 0,
        settings: RemoteCameraSettings = RemoteCameraSettings(),
        format: RemoteCameraFormat? = nil,
        captureProfileID: RemoteCameraCaptureProfileID? = nil,
        captureCodecLabel: String? = nil,
        captureFormatLabel: String? = nil,
        deviceStartTime: UInt64? = nil,
        deviceStopTime: UInt64? = nil,
        hostStartTime: UInt64? = nil,
        hostStopTime: UInt64? = nil,
        hostTimelineStartTime: UInt64? = nil,
        estimatedHostStartTime: UInt64? = nil,
        stopReason: String? = nil,
        recordingDiagnostics: RemoteCameraRecordingDiagnostics? = nil
    ) {
        self.takeID = takeID
        self.recordingID = recordingID
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
        self.durationSeconds = durationSeconds
        self.resumeOffset = resumeOffset
        self.settings = settings
        self.format = format
        self.captureProfileID = captureProfileID ?? settings.captureProfileID
        self.captureCodecLabel = captureCodecLabel
        self.captureFormatLabel = captureFormatLabel
        self.deviceStartTime = deviceStartTime
        self.deviceStopTime = deviceStopTime
        self.hostStartTime = hostStartTime
        self.hostStopTime = hostStopTime
        self.hostTimelineStartTime = hostTimelineStartTime
        self.estimatedHostStartTime = estimatedHostStartTime
        self.stopReason = stopReason
        self.recordingDiagnostics = recordingDiagnostics
    }
}

extension RemoteCameraTransferManifest {
    private enum CodingKeys: String, CodingKey {
        case takeID
        case recordingID
        case fileName
        case byteCount
        case sha256
        case durationSeconds
        case resumeOffset
        case settings
        case format
        case captureProfileID
        case captureCodecLabel
        case captureFormatLabel
        case deviceStartTime
        case deviceStopTime
        case hostStartTime
        case hostStopTime
        case hostTimelineStartTime
        case estimatedHostStartTime
        case stopReason
        case recordingDiagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let settings = try container.decodeIfPresent(RemoteCameraSettings.self, forKey: .settings) ?? RemoteCameraSettings()
        self.init(
            takeID: try container.decode(UUID.self, forKey: .takeID),
            recordingID: try container.decode(UUID.self, forKey: .recordingID),
            fileName: try container.decode(String.self, forKey: .fileName),
            byteCount: try container.decode(Int64.self, forKey: .byteCount),
            sha256: try container.decodeIfPresent(String.self, forKey: .sha256),
            durationSeconds: try container.decode(Double.self, forKey: .durationSeconds),
            resumeOffset: try container.decodeIfPresent(Int64.self, forKey: .resumeOffset) ?? 0,
            settings: settings,
            format: try container.decodeIfPresent(RemoteCameraFormat.self, forKey: .format),
            captureProfileID: try container.decodeIfPresent(
                RemoteCameraCaptureProfileID.self,
                forKey: .captureProfileID
            ) ?? settings.captureProfileID,
            captureCodecLabel: try container.decodeIfPresent(String.self, forKey: .captureCodecLabel),
            captureFormatLabel: try container.decodeIfPresent(String.self, forKey: .captureFormatLabel),
            deviceStartTime: try container.decodeIfPresent(UInt64.self, forKey: .deviceStartTime),
            deviceStopTime: try container.decodeIfPresent(UInt64.self, forKey: .deviceStopTime),
            hostStartTime: try container.decodeIfPresent(UInt64.self, forKey: .hostStartTime),
            hostStopTime: try container.decodeIfPresent(UInt64.self, forKey: .hostStopTime),
            hostTimelineStartTime: try container.decodeIfPresent(UInt64.self, forKey: .hostTimelineStartTime),
            estimatedHostStartTime: try container.decodeIfPresent(UInt64.self, forKey: .estimatedHostStartTime),
            stopReason: try container.decodeIfPresent(String.self, forKey: .stopReason),
            recordingDiagnostics: try container.decodeIfPresent(
                RemoteCameraRecordingDiagnostics.self,
                forKey: .recordingDiagnostics
            )
        )
    }
}

public struct RemoteCameraTransferProgress: Codable, Equatable, Sendable {
    public var takeID: UUID
    public var transferredByteCount: Int64
    public var expectedByteCount: Int64

    public init(takeID: UUID, transferredByteCount: Int64, expectedByteCount: Int64) {
        self.takeID = takeID
        self.transferredByteCount = transferredByteCount
        self.expectedByteCount = expectedByteCount
    }

    public var fraction: Double {
        guard expectedByteCount > 0 else { return 0 }
        return min(1, max(0, Double(transferredByteCount) / Double(expectedByteCount)))
    }
}
