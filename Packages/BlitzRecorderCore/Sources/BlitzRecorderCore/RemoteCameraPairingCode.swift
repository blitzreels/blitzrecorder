import Foundation

public enum RemoteCameraPairingCode {
    public static let length = 6

    public static func normalized(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    public static func isValid(_ value: String) -> Bool {
        normalized(value).count == length
    }
}
