import Foundation

public enum RemoteCameraLens: String, Codable, CaseIterable, Sendable {
    case ultraWide
    case wide
    case telephoto
    case frontWide

    public var displayName: String {
        switch self {
        case .ultraWide: return "Ultra Wide"
        case .wide: return "Wide"
        case .telephoto: return "Telephoto"
        case .frontWide: return "Front"
        }
    }
}

public enum RemoteCameraFocusMode: String, Codable, CaseIterable, Sendable {
    case continuousAuto
    case locked
    case manual

    public var displayName: String {
        switch self {
        case .continuousAuto: return "Auto"
        case .locked: return "Locked"
        case .manual: return "Manual"
        }
    }
}

public enum RemoteCameraExposureMode: String, Codable, CaseIterable, Sendable {
    case continuousAuto
    case locked
    case manual

    public var displayName: String {
        switch self {
        case .continuousAuto: return "Auto"
        case .locked: return "Locked"
        case .manual: return "Manual"
        }
    }
}

public enum RemoteCameraWhiteBalanceMode: String, Codable, CaseIterable, Sendable {
    case continuousAuto
    case locked
    case manual

    public var displayName: String {
        switch self {
        case .continuousAuto: return "Auto"
        case .locked: return "Locked"
        case .manual: return "Manual"
        }
    }
}

public enum RemoteCameraStabilizationMode: String, Codable, CaseIterable, Sendable {
    case off
    case standard
    case cinematic
    case cinematicExtendedEnhanced
    case auto

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard"
        case .cinematic: return "Cinematic"
        case .cinematicExtendedEnhanced: return "Cinematic Enhanced"
        case .auto: return "Auto"
        }
    }
}

public enum RemoteCameraCaptureProfileID: String, Codable, CaseIterable, Sendable {
    case automatic
    case highEfficiency
    case proRes422

    public var displayName: String {
        switch self {
        case .automatic: return "Auto"
        case .highEfficiency: return "HEVC"
        case .proRes422: return "ProRes"
        }
    }
}

public enum RemoteCameraColorMode: String, Codable, CaseIterable, Sendable {
    case standard
    case appleLog
    case appleLog2

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .appleLog: return "Apple Log"
        case .appleLog2: return "Apple Log 2"
        }
    }
}

public struct RemoteCameraCaptureProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: RemoteCameraCaptureProfileID
    public var displayName: String
    public var isAvailable: Bool
    public var unavailableReason: String?
    public var codecLabel: String?
    public var supportedFormatIDs: [String]
    public var supportedFormatFrameRates: [String: [Int]]

    public init(
        id: RemoteCameraCaptureProfileID,
        displayName: String = "",
        isAvailable: Bool = true,
        unavailableReason: String? = nil,
        codecLabel: String? = nil,
        supportedFormatIDs: [String] = [],
        supportedFormatFrameRates: [String: [Int]] = [:]
    ) {
        self.id = id
        self.displayName = displayName.isEmpty ? id.displayName : displayName
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
        self.codecLabel = codecLabel
        self.supportedFormatIDs = supportedFormatIDs
        self.supportedFormatFrameRates = supportedFormatFrameRates
    }
}

extension RemoteCameraCaptureProfile {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case isAvailable
        case unavailableReason
        case codecLabel
        case supportedFormatIDs
        case supportedFormatFrameRates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(RemoteCameraCaptureProfileID.self, forKey: .id)
        self.init(
            id: id,
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? id.displayName,
            isAvailable: try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true,
            unavailableReason: try container.decodeIfPresent(String.self, forKey: .unavailableReason),
            codecLabel: try container.decodeIfPresent(String.self, forKey: .codecLabel),
            supportedFormatIDs: try container.decodeIfPresent([String].self, forKey: .supportedFormatIDs) ?? [],
            supportedFormatFrameRates: try container.decodeIfPresent(
                [String: [Int]].self,
                forKey: .supportedFormatFrameRates
            ) ?? [:]
        )
    }
}

public struct RemoteCameraFormat: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var width: Int
    public var height: Int
    public var frameRates: [Int]
    public var colorModes: [RemoteCameraColorMode]
    public var colorModeFrameRates: [RemoteCameraColorMode: [Int]]
    public var supportsStabilization: Bool
    public var supportsHDR: Bool
    public var supportsCinematicVideo: Bool

    public init(
        id: String,
        width: Int,
        height: Int,
        frameRates: [Int],
        colorModes: [RemoteCameraColorMode] = [.standard],
        colorModeFrameRates: [RemoteCameraColorMode: [Int]] = [:],
        supportsStabilization: Bool,
        supportsHDR: Bool,
        supportsCinematicVideo: Bool = false
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.frameRates = frameRates
        self.colorModes = colorModes.isEmpty ? [.standard] : colorModes
        self.colorModeFrameRates = colorModeFrameRates
        self.supportsStabilization = supportsStabilization
        self.supportsHDR = supportsHDR
        self.supportsCinematicVideo = supportsCinematicVideo
    }
}

extension RemoteCameraFormat {
    private enum CodingKeys: String, CodingKey {
        case id
        case width
        case height
        case frameRates
        case colorModes
        case colorModeFrameRates
        case supportsStabilization
        case supportsHDR
        case supportsCinematicVideo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            width: try container.decode(Int.self, forKey: .width),
            height: try container.decode(Int.self, forKey: .height),
            frameRates: try container.decode([Int].self, forKey: .frameRates),
            colorModes: try container.decodeIfPresent([RemoteCameraColorMode].self, forKey: .colorModes) ?? [.standard],
            colorModeFrameRates: try container.decodeIfPresent(
                [RemoteCameraColorMode: [Int]].self,
                forKey: .colorModeFrameRates
            ) ?? [:],
            supportsStabilization: try container.decode(Bool.self, forKey: .supportsStabilization),
            supportsHDR: try container.decode(Bool.self, forKey: .supportsHDR),
            supportsCinematicVideo: try container.decodeIfPresent(
                Bool.self,
                forKey: .supportsCinematicVideo
            ) ?? false
        )
    }
}

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
