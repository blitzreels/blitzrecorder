import Foundation

public enum RemoteCameraConnectionState: String, Codable, Sendable {
    case unavailable
    case discovering
    case pairing
    case connected
    case degraded
    case disconnected
}

public struct RemoteCameraDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var hostName: String?
    public var port: UInt16?
    public var capabilities: RemoteCameraCapabilities?
    public var isTrusted: Bool

    public init(
        id: UUID,
        name: String,
        hostName: String? = nil,
        port: UInt16? = nil,
        capabilities: RemoteCameraCapabilities? = nil,
        isTrusted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hostName = hostName
        self.port = port
        self.capabilities = capabilities
        self.isTrusted = isTrusted
    }
}
