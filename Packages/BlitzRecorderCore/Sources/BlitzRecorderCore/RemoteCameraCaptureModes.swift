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
