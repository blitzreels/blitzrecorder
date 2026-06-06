import Foundation

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
        stopReason: String? = nil
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
            stopReason: try container.decodeIfPresent(String.self, forKey: .stopReason)
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
