import Foundation

public enum RemoteCameraConstants {
    public static let protocolVersion = 2
    public static let bonjourServiceType = "_blitzrecorder-camera._tcp"
    public static let defaultControlPort: UInt16 = 47391
    public static let companionURLScheme = "blitzrecorder-camera"

    /// Sent by the iPhone when the Mac speaks another protocol version. Older iPhone apps send the same words.
    public static func unsupportedProtocolReason(_ version: Int) -> String {
        "Unsupported protocol \(version)"
    }

    public static func isUnsupportedProtocolReason(_ reason: String) -> Bool {
        reason.hasPrefix("Unsupported protocol")
    }
}
