import Foundation

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
