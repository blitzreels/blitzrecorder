import Foundation

public enum RemoteCameraProviderID {
    public static let prefix = "remote-iphone:"

    public static func make(for serviceID: String) -> String {
        prefix + serviceID
    }

    public static func isRemote(_ id: String?) -> Bool {
        id?.hasPrefix(prefix) == true
    }

    public static func serviceID(from id: String?) -> String? {
        guard let id, id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }
}
