import Foundation

public enum RemoteCameraConnectionState: String, Codable, Sendable {
    case unavailable
    case discovering
    case pairing
    case connected
    case degraded
    case disconnected
}
