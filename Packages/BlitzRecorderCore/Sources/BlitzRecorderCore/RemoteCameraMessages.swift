import Foundation

public enum RemoteCameraRecordingPhase: String, Codable, Sendable {
    case idle
    case preparing
    case recording
    case stopping
    case transferring
    case pendingImport
    case failed
}

public struct RemoteCameraTimeline: Codable, Equatable, Sendable {
    public var takeID: UUID
    public var hostStartTime: UInt64?
    public var hostStopTime: UInt64?
    public var hostTimelineStartTime: UInt64?

    public init(
        takeID: UUID,
        hostStartTime: UInt64? = nil,
        hostStopTime: UInt64? = nil,
        hostTimelineStartTime: UInt64? = nil
    ) {
        self.takeID = takeID
        self.hostStartTime = hostStartTime
        self.hostStopTime = hostStopTime
        self.hostTimelineStartTime = hostTimelineStartTime
    }
}

public struct RemoteCameraSettings: Codable, Equatable, Sendable {
    public static let defaultRotationDegrees = 180

    public var lens: RemoteCameraLens
    public var formatID: String?
    public var frameRate: Int
    public var captureProfileID: RemoteCameraCaptureProfileID
    public var colorMode: RemoteCameraColorMode
    public var zoomFactor: Double
    public var focusMode: RemoteCameraFocusMode
    public var focusPosition: Double
    public var exposureMode: RemoteCameraExposureMode
    public var exposureBias: Double
    public var iso: Double?
    public var shutterDurationSeconds: Double?
    public var whiteBalanceMode: RemoteCameraWhiteBalanceMode
    public var whiteBalanceTemperature: Double
    public var whiteBalanceTint: Double
    public var stabilizationMode: RemoteCameraStabilizationMode
    public var usesAutomaticRotation: Bool
    public var rotationDegrees: Int
    public var torchEnabled: Bool
    public var cinematicVideoEnabled: Bool
    public var cinematicAperture: Double?

    public init(
        lens: RemoteCameraLens = .wide,
        formatID: String? = nil,
        frameRate: Int = 30,
        captureProfileID: RemoteCameraCaptureProfileID = .automatic,
        colorMode: RemoteCameraColorMode = .standard,
        zoomFactor: Double = 1,
        focusMode: RemoteCameraFocusMode = .continuousAuto,
        focusPosition: Double = 0.5,
        exposureMode: RemoteCameraExposureMode = .continuousAuto,
        exposureBias: Double = 0,
        iso: Double? = nil,
        shutterDurationSeconds: Double? = nil,
        whiteBalanceMode: RemoteCameraWhiteBalanceMode = .continuousAuto,
        whiteBalanceTemperature: Double = 5_500,
        whiteBalanceTint: Double = 0,
        stabilizationMode: RemoteCameraStabilizationMode = .auto,
        usesAutomaticRotation: Bool = true,
        rotationDegrees: Int = RemoteCameraSettings.defaultRotationDegrees,
        torchEnabled: Bool = false,
        cinematicVideoEnabled: Bool = false,
        cinematicAperture: Double? = nil
    ) {
        self.lens = lens
        self.formatID = formatID
        self.frameRate = frameRate
        self.captureProfileID = captureProfileID
        self.colorMode = colorMode
        self.zoomFactor = zoomFactor
        self.focusMode = focusMode
        self.focusPosition = focusPosition
        self.exposureMode = exposureMode
        self.exposureBias = exposureBias
        self.iso = iso
        self.shutterDurationSeconds = shutterDurationSeconds
        self.whiteBalanceMode = whiteBalanceMode
        self.whiteBalanceTemperature = whiteBalanceTemperature
        self.whiteBalanceTint = whiteBalanceTint
        self.stabilizationMode = stabilizationMode
        self.usesAutomaticRotation = usesAutomaticRotation
        self.rotationDegrees = Self.normalizedRotationDegrees(rotationDegrees)
        self.torchEnabled = torchEnabled
        self.cinematicVideoEnabled = cinematicVideoEnabled
        self.cinematicAperture = cinematicAperture
    }

    public static func normalizedRotationDegrees(_ degrees: Int) -> Int {
        let normalized = ((degrees % 360) + 360) % 360
        return [0, 90, 180, 270].min(by: { abs($0 - normalized) < abs($1 - normalized) }) ?? 0
    }
}

extension RemoteCameraSettings {
    private enum CodingKeys: String, CodingKey {
        case lens
        case formatID
        case frameRate
        case captureProfileID
        case colorMode
        case zoomFactor
        case focusMode
        case focusPosition
        case exposureMode
        case exposureBias
        case iso
        case shutterDurationSeconds
        case whiteBalanceMode
        case whiteBalanceTemperature
        case whiteBalanceTint
        case stabilizationMode
        case usesAutomaticRotation
        case rotationDegrees
        case torchEnabled
        case cinematicVideoEnabled
        case cinematicAperture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lens: try container.decodeIfPresent(RemoteCameraLens.self, forKey: .lens) ?? .wide,
            formatID: try container.decodeIfPresent(String.self, forKey: .formatID),
            frameRate: try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? 30,
            captureProfileID: try container.decodeIfPresent(
                RemoteCameraCaptureProfileID.self,
                forKey: .captureProfileID
            ) ?? .automatic,
            colorMode: try container.decodeIfPresent(RemoteCameraColorMode.self, forKey: .colorMode) ?? .standard,
            zoomFactor: try container.decodeIfPresent(Double.self, forKey: .zoomFactor) ?? 1,
            focusMode: try container.decodeIfPresent(RemoteCameraFocusMode.self, forKey: .focusMode) ?? .continuousAuto,
            focusPosition: try container.decodeIfPresent(Double.self, forKey: .focusPosition) ?? 0.5,
            exposureMode: try container.decodeIfPresent(RemoteCameraExposureMode.self, forKey: .exposureMode) ?? .continuousAuto,
            exposureBias: try container.decodeIfPresent(Double.self, forKey: .exposureBias) ?? 0,
            iso: try container.decodeIfPresent(Double.self, forKey: .iso),
            shutterDurationSeconds: try container.decodeIfPresent(Double.self, forKey: .shutterDurationSeconds),
            whiteBalanceMode: try container.decodeIfPresent(
                RemoteCameraWhiteBalanceMode.self,
                forKey: .whiteBalanceMode
            ) ?? .continuousAuto,
            whiteBalanceTemperature: try container.decodeIfPresent(
                Double.self,
                forKey: .whiteBalanceTemperature
            ) ?? 5_500,
            whiteBalanceTint: try container.decodeIfPresent(Double.self, forKey: .whiteBalanceTint) ?? 0,
            stabilizationMode: try container.decodeIfPresent(
                RemoteCameraStabilizationMode.self,
                forKey: .stabilizationMode
            ) ?? .auto,
            usesAutomaticRotation: try container.decodeIfPresent(Bool.self, forKey: .usesAutomaticRotation) ?? true,
            rotationDegrees: try container.decodeIfPresent(Int.self, forKey: .rotationDegrees)
                ?? Self.defaultRotationDegrees,
            torchEnabled: try container.decodeIfPresent(Bool.self, forKey: .torchEnabled) ?? false,
            cinematicVideoEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .cinematicVideoEnabled
            ) ?? false,
            cinematicAperture: try container.decodeIfPresent(Double.self, forKey: .cinematicAperture)
        )
    }
}

public enum RemoteCameraCommand: Codable, Equatable, Sendable {
    case hello(protocolVersion: Int, macIdentity: RemoteCameraMacIdentity)
    case pair(shortCode: String, macIdentity: RemoteCameraMacIdentity, proof: RemoteCameraPairingProof)
    case requestCapabilities
    case applySettings(RemoteCameraSettings)
    case prepare(RemoteCameraTimeline)
    case start(RemoteCameraTimeline)
    case stop(RemoteCameraTimeline)
    case requestTransfer(takeID: UUID, resumeOffset: Int64)
    case transferAck(takeID: UUID, receivedByteCount: Int64)
    case cancel
}

public struct RemoteCameraTelemetry: Codable, Equatable, Sendable {
    public var phase: RemoteCameraRecordingPhase
    public var elapsedSeconds: Double
    public var batteryLevel: Double?
    public var thermalState: String
    public var storageFreeBytes: Int64?
    public var activeSettings: RemoteCameraSettings
    public var transferProgress: RemoteCameraTransferProgress?
    public var previewHealth: RemoteCameraPreviewHealth?
    public var captureWarning: String?

    public init(
        phase: RemoteCameraRecordingPhase,
        elapsedSeconds: Double,
        batteryLevel: Double?,
        thermalState: String,
        storageFreeBytes: Int64?,
        activeSettings: RemoteCameraSettings,
        transferProgress: RemoteCameraTransferProgress? = nil,
        previewHealth: RemoteCameraPreviewHealth? = nil,
        captureWarning: String? = nil
    ) {
        self.phase = phase
        self.elapsedSeconds = elapsedSeconds
        self.batteryLevel = batteryLevel
        self.thermalState = thermalState
        self.storageFreeBytes = storageFreeBytes
        self.activeSettings = activeSettings
        self.transferProgress = transferProgress
        self.previewHealth = previewHealth
        self.captureWarning = captureWarning
    }
}

public struct RemoteCameraPreviewHealth: Codable, Equatable, Sendable {
    public var framesSent: Int64
    public var framesDropped: Int64
    public var lastFrameAgeSeconds: Double?
    public var isTransferActive: Bool

    public init(
        framesSent: Int64,
        framesDropped: Int64,
        lastFrameAgeSeconds: Double?,
        isTransferActive: Bool = false
    ) {
        self.framesSent = framesSent
        self.framesDropped = framesDropped
        self.lastFrameAgeSeconds = lastFrameAgeSeconds
        self.isTransferActive = isTransferActive
    }

    public var droppedFrameRatio: Double {
        let total = framesSent + framesDropped
        guard total > 0 else { return 0 }
        return Double(framesDropped) / Double(total)
    }

    public var isDroppingFrames: Bool {
        droppedFrameRatio >= 0.25
    }

    public var isStale: Bool {
        framesSent > 0 && (lastFrameAgeSeconds ?? .infinity) >= 2
    }

    public var isWaitingForFirstFrame: Bool {
        !isTransferActive && framesSent == 0 && framesDropped == 0
    }

    public var isBlockedBeforeFirstFrame: Bool {
        !isTransferActive && framesSent == 0 && framesDropped > 0
    }

    public var isHealthy: Bool {
        !isTransferActive && framesSent > 0 && !isStale && !isDroppingFrames
    }

    private enum CodingKeys: String, CodingKey {
        case framesSent
        case framesDropped
        case lastFrameAgeSeconds
        case isTransferActive
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            framesSent: try container.decode(Int64.self, forKey: .framesSent),
            framesDropped: try container.decode(Int64.self, forKey: .framesDropped),
            lastFrameAgeSeconds: try container.decodeIfPresent(Double.self, forKey: .lastFrameAgeSeconds),
            isTransferActive: try container.decodeIfPresent(Bool.self, forKey: .isTransferActive) ?? false
        )
    }
}

public enum RemoteCameraMonitorCodec: String, Codable, Equatable, Sendable {
    case h264
}

public struct RemoteCameraMonitorVideoFrame: Codable, Equatable, Sendable {
    public var codec: RemoteCameraMonitorCodec
    public var data: Data
    public var width: Int
    public var height: Int
    public var presentationTimeSeconds: Double
    public var frameDurationSeconds: Double?
    public var isKeyFrame: Bool
    public var sequenceNumber: Int64
    public var h264SPS: Data?
    public var h264PPS: Data?

    public init(
        codec: RemoteCameraMonitorCodec,
        data: Data,
        width: Int,
        height: Int,
        presentationTimeSeconds: Double,
        frameDurationSeconds: Double? = nil,
        isKeyFrame: Bool,
        sequenceNumber: Int64,
        h264SPS: Data? = nil,
        h264PPS: Data? = nil
    ) {
        self.codec = codec
        self.data = data
        self.width = width
        self.height = height
        self.presentationTimeSeconds = presentationTimeSeconds
        self.frameDurationSeconds = frameDurationSeconds
        self.isKeyFrame = isKeyFrame
        self.sequenceNumber = sequenceNumber
        self.h264SPS = h264SPS
        self.h264PPS = h264PPS
    }
}

public enum RemoteCameraEvent: Codable, Equatable, Sendable {
    case pairingChallenge(RemoteCameraPairingChallenge)
    case paired(RemoteCameraPairingTrust)
    case capabilities(RemoteCameraCapabilities)
    case telemetry(RemoteCameraTelemetry)
    case prepared(takeID: UUID, deviceStartTime: UInt64)
    case started(takeID: UUID, deviceStartTime: UInt64)
    case stopped(takeID: UUID, deviceStopTime: UInt64, durationSeconds: Double, reason: String?)
    case monitorFrame(jpegData: Data, width: Int, height: Int)
    case monitorVideoFrame(RemoteCameraMonitorVideoFrame)
    case transferReady(takeID: UUID, fileName: String, byteCount: Int64, manifest: RemoteCameraTransferManifest)
    case transferChunk(takeID: UUID, offset: Int64, data: Data, isFinal: Bool)
    case transferComplete(takeID: UUID, byteCount: Int64, sha256: String?)
    case failed(takeID: UUID?, reason: String)
}
