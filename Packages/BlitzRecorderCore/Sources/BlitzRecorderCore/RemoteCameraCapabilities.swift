import Foundation

public struct RemoteCameraLensCapabilities: Codable, Equatable, Sendable {
    public var lens: RemoteCameraLens
    public var supportedFormats: [RemoteCameraFormat]
    public var supportedCaptureProfiles: [RemoteCameraCaptureProfile]
    public var supportsTorch: Bool
    public var minimumZoomFactor: Double
    public var maximumZoomFactor: Double
    public var supportsManualFocus: Bool
    public var supportsFocusLock: Bool
    public var supportsManualExposure: Bool
    public var supportsExposureLock: Bool
    public var supportsWhiteBalanceLock: Bool
    public var supportsManualWhiteBalance: Bool
    public var supportedStabilizationModes: [RemoteCameraStabilizationMode]
    public var minimumExposureBias: Double
    public var maximumExposureBias: Double
    public var minimumISO: Double?
    public var maximumISO: Double?
    public var minimumShutterDurationSeconds: Double?
    public var maximumShutterDurationSeconds: Double?
    public var supportsCinematicVideo: Bool
    public var minimumCinematicAperture: Double?
    public var maximumCinematicAperture: Double?
    public var defaultCinematicAperture: Double?

    public init(
        lens: RemoteCameraLens,
        supportedFormats: [RemoteCameraFormat],
        supportedCaptureProfiles: [RemoteCameraCaptureProfile],
        supportsTorch: Bool,
        minimumZoomFactor: Double,
        maximumZoomFactor: Double,
        supportsManualFocus: Bool,
        supportsFocusLock: Bool,
        supportsManualExposure: Bool,
        supportsExposureLock: Bool,
        supportsWhiteBalanceLock: Bool,
        supportsManualWhiteBalance: Bool,
        supportedStabilizationModes: [RemoteCameraStabilizationMode],
        minimumExposureBias: Double,
        maximumExposureBias: Double,
        minimumISO: Double? = nil,
        maximumISO: Double? = nil,
        minimumShutterDurationSeconds: Double? = nil,
        maximumShutterDurationSeconds: Double? = nil,
        supportsCinematicVideo: Bool = false,
        minimumCinematicAperture: Double? = nil,
        maximumCinematicAperture: Double? = nil,
        defaultCinematicAperture: Double? = nil
    ) {
        self.lens = lens
        self.supportedFormats = supportedFormats
        self.supportedCaptureProfiles = supportedCaptureProfiles
        self.supportsTorch = supportsTorch
        self.minimumZoomFactor = minimumZoomFactor
        self.maximumZoomFactor = maximumZoomFactor
        self.supportsManualFocus = supportsManualFocus
        self.supportsFocusLock = supportsFocusLock
        self.supportsManualExposure = supportsManualExposure
        self.supportsExposureLock = supportsExposureLock
        self.supportsWhiteBalanceLock = supportsWhiteBalanceLock
        self.supportsManualWhiteBalance = supportsManualWhiteBalance
        self.supportedStabilizationModes = supportedStabilizationModes
        self.minimumExposureBias = minimumExposureBias
        self.maximumExposureBias = maximumExposureBias
        self.minimumISO = minimumISO
        self.maximumISO = maximumISO
        self.minimumShutterDurationSeconds = minimumShutterDurationSeconds
        self.maximumShutterDurationSeconds = maximumShutterDurationSeconds
        self.supportsCinematicVideo = supportsCinematicVideo
        self.minimumCinematicAperture = minimumCinematicAperture
        self.maximumCinematicAperture = maximumCinematicAperture
        self.defaultCinematicAperture = defaultCinematicAperture
    }
}

public struct RemoteCameraCapabilities: Codable, Equatable, Sendable {
    public var deviceName: String
    public var deviceModelIdentifier: String?
    public var supportedLenses: [RemoteCameraLens]
    public var lensCapabilities: [RemoteCameraLensCapabilities]
    public var supportedFormats: [RemoteCameraFormat]
    public var supportedCaptureProfiles: [RemoteCameraCaptureProfile]
    public var supportsTorch: Bool
    public var minimumZoomFactor: Double
    public var maximumZoomFactor: Double
    public var supportsManualFocus: Bool
    public var supportsFocusLock: Bool
    public var supportsManualExposure: Bool
    public var supportsExposureLock: Bool
    public var supportsWhiteBalanceLock: Bool
    public var supportsManualWhiteBalance: Bool
    public var supportedStabilizationModes: [RemoteCameraStabilizationMode]
    public var supportedRotationDegrees: [Int]
    public var minimumExposureBias: Double
    public var maximumExposureBias: Double
    public var minimumISO: Double?
    public var maximumISO: Double?
    public var minimumShutterDurationSeconds: Double?
    public var maximumShutterDurationSeconds: Double?
    public var supportsCinematicVideo: Bool
    public var minimumCinematicAperture: Double?
    public var maximumCinematicAperture: Double?
    public var defaultCinematicAperture: Double?

    public init(
        deviceName: String,
        deviceModelIdentifier: String? = nil,
        supportedLenses: [RemoteCameraLens],
        lensCapabilities: [RemoteCameraLensCapabilities] = [],
        supportedFormats: [RemoteCameraFormat],
        supportedCaptureProfiles: [RemoteCameraCaptureProfile] = [
            RemoteCameraCaptureProfile(id: .automatic)
        ],
        supportsTorch: Bool,
        minimumZoomFactor: Double = 1,
        maximumZoomFactor: Double = 1,
        supportsManualFocus: Bool,
        supportsFocusLock: Bool,
        supportsManualExposure: Bool,
        supportsExposureLock: Bool,
        supportsWhiteBalanceLock: Bool,
        supportsManualWhiteBalance: Bool,
        supportedStabilizationModes: [RemoteCameraStabilizationMode],
        supportedRotationDegrees: [Int] = [0, 90, 180, 270],
        minimumExposureBias: Double,
        maximumExposureBias: Double,
        minimumISO: Double? = nil,
        maximumISO: Double? = nil,
        minimumShutterDurationSeconds: Double? = nil,
        maximumShutterDurationSeconds: Double? = nil,
        supportsCinematicVideo: Bool = false,
        minimumCinematicAperture: Double? = nil,
        maximumCinematicAperture: Double? = nil,
        defaultCinematicAperture: Double? = nil
    ) {
        self.deviceName = deviceName
        self.deviceModelIdentifier = deviceModelIdentifier
        self.supportedLenses = supportedLenses
        self.lensCapabilities = lensCapabilities
        self.supportedFormats = supportedFormats
        self.supportedCaptureProfiles = supportedCaptureProfiles
        self.supportsTorch = supportsTorch
        self.minimumZoomFactor = minimumZoomFactor
        self.maximumZoomFactor = maximumZoomFactor
        self.supportsManualFocus = supportsManualFocus
        self.supportsFocusLock = supportsFocusLock
        self.supportsManualExposure = supportsManualExposure
        self.supportsExposureLock = supportsExposureLock
        self.supportsWhiteBalanceLock = supportsWhiteBalanceLock
        self.supportsManualWhiteBalance = supportsManualWhiteBalance
        self.supportedStabilizationModes = supportedStabilizationModes
        self.supportedRotationDegrees = supportedRotationDegrees
        self.minimumExposureBias = minimumExposureBias
        self.maximumExposureBias = maximumExposureBias
        self.minimumISO = minimumISO
        self.maximumISO = maximumISO
        self.minimumShutterDurationSeconds = minimumShutterDurationSeconds
        self.maximumShutterDurationSeconds = maximumShutterDurationSeconds
        self.supportsCinematicVideo = supportsCinematicVideo
        self.minimumCinematicAperture = minimumCinematicAperture
        self.maximumCinematicAperture = maximumCinematicAperture
        self.defaultCinematicAperture = defaultCinematicAperture
    }
}

extension RemoteCameraCapabilities {
    private enum CodingKeys: String, CodingKey {
        case deviceName
        case deviceModelIdentifier
        case supportedLenses
        case lensCapabilities
        case supportedFormats
        case supportedCaptureProfiles
        case supportsTorch
        case minimumZoomFactor
        case maximumZoomFactor
        case supportsManualFocus
        case supportsFocusLock
        case supportsManualExposure
        case supportsExposureLock
        case supportsWhiteBalanceLock
        case supportsManualWhiteBalance
        case supportedStabilizationModes
        case supportedRotationDegrees
        case minimumExposureBias
        case maximumExposureBias
        case minimumISO
        case maximumISO
        case minimumShutterDurationSeconds
        case maximumShutterDurationSeconds
        case supportsCinematicVideo
        case minimumCinematicAperture
        case maximumCinematicAperture
        case defaultCinematicAperture
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            deviceName: try container.decode(String.self, forKey: .deviceName),
            deviceModelIdentifier: try container.decodeIfPresent(String.self, forKey: .deviceModelIdentifier),
            supportedLenses: try container.decode([RemoteCameraLens].self, forKey: .supportedLenses),
            lensCapabilities: try container.decodeIfPresent(
                [RemoteCameraLensCapabilities].self,
                forKey: .lensCapabilities
            ) ?? [],
            supportedFormats: try container.decode([RemoteCameraFormat].self, forKey: .supportedFormats),
            supportedCaptureProfiles: try container.decodeIfPresent(
                [RemoteCameraCaptureProfile].self,
                forKey: .supportedCaptureProfiles
            ) ?? [RemoteCameraCaptureProfile(id: .automatic)],
            supportsTorch: try container.decode(Bool.self, forKey: .supportsTorch),
            minimumZoomFactor: try container.decodeIfPresent(Double.self, forKey: .minimumZoomFactor) ?? 1,
            maximumZoomFactor: try container.decodeIfPresent(Double.self, forKey: .maximumZoomFactor) ?? 1,
            supportsManualFocus: try container.decode(Bool.self, forKey: .supportsManualFocus),
            supportsFocusLock: try container.decode(Bool.self, forKey: .supportsFocusLock),
            supportsManualExposure: try container.decode(Bool.self, forKey: .supportsManualExposure),
            supportsExposureLock: try container.decode(Bool.self, forKey: .supportsExposureLock),
            supportsWhiteBalanceLock: try container.decode(Bool.self, forKey: .supportsWhiteBalanceLock),
            supportsManualWhiteBalance: try container.decode(Bool.self, forKey: .supportsManualWhiteBalance),
            supportedStabilizationModes: try container.decode(
                [RemoteCameraStabilizationMode].self,
                forKey: .supportedStabilizationModes
            ),
            supportedRotationDegrees: try container.decodeIfPresent(
                [Int].self,
                forKey: .supportedRotationDegrees
            ) ?? [0, 90, 180, 270],
            minimumExposureBias: try container.decode(Double.self, forKey: .minimumExposureBias),
            maximumExposureBias: try container.decode(Double.self, forKey: .maximumExposureBias),
            minimumISO: try container.decodeIfPresent(Double.self, forKey: .minimumISO),
            maximumISO: try container.decodeIfPresent(Double.self, forKey: .maximumISO),
            minimumShutterDurationSeconds: try container.decodeIfPresent(
                Double.self,
                forKey: .minimumShutterDurationSeconds
            ),
            maximumShutterDurationSeconds: try container.decodeIfPresent(
                Double.self,
                forKey: .maximumShutterDurationSeconds
            ),
            supportsCinematicVideo: try container.decodeIfPresent(
                Bool.self,
                forKey: .supportsCinematicVideo
            ) ?? false,
            minimumCinematicAperture: try container.decodeIfPresent(
                Double.self,
                forKey: .minimumCinematicAperture
            ),
            maximumCinematicAperture: try container.decodeIfPresent(
                Double.self,
                forKey: .maximumCinematicAperture
            ),
            defaultCinematicAperture: try container.decodeIfPresent(
                Double.self,
                forKey: .defaultCinematicAperture
            )
        )
    }
}

extension RemoteCameraCapabilities {
    public func capabilities(for lens: RemoteCameraLens) -> RemoteCameraCapabilities {
        guard let lensCapabilities = lensCapabilities.first(where: { $0.lens == lens }) else {
            return self
        }
        return RemoteCameraCapabilities(
            deviceName: deviceName,
            deviceModelIdentifier: deviceModelIdentifier,
            supportedLenses: supportedLenses,
            lensCapabilities: self.lensCapabilities,
            supportedFormats: lensCapabilities.supportedFormats,
            supportedCaptureProfiles: lensCapabilities.supportedCaptureProfiles,
            supportsTorch: lensCapabilities.supportsTorch,
            minimumZoomFactor: lensCapabilities.minimumZoomFactor,
            maximumZoomFactor: lensCapabilities.maximumZoomFactor,
            supportsManualFocus: lensCapabilities.supportsManualFocus,
            supportsFocusLock: lensCapabilities.supportsFocusLock,
            supportsManualExposure: lensCapabilities.supportsManualExposure,
            supportsExposureLock: lensCapabilities.supportsExposureLock,
            supportsWhiteBalanceLock: lensCapabilities.supportsWhiteBalanceLock,
            supportsManualWhiteBalance: lensCapabilities.supportsManualWhiteBalance,
            supportedStabilizationModes: lensCapabilities.supportedStabilizationModes,
            supportedRotationDegrees: supportedRotationDegrees,
            minimumExposureBias: lensCapabilities.minimumExposureBias,
            maximumExposureBias: lensCapabilities.maximumExposureBias,
            minimumISO: lensCapabilities.minimumISO,
            maximumISO: lensCapabilities.maximumISO,
            minimumShutterDurationSeconds: lensCapabilities.minimumShutterDurationSeconds,
            maximumShutterDurationSeconds: lensCapabilities.maximumShutterDurationSeconds,
            supportsCinematicVideo: lensCapabilities.supportsCinematicVideo,
            minimumCinematicAperture: lensCapabilities.minimumCinematicAperture,
            maximumCinematicAperture: lensCapabilities.maximumCinematicAperture,
            defaultCinematicAperture: lensCapabilities.defaultCinematicAperture
        )
    }
}
