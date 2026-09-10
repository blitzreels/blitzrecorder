import Foundation

struct SourcePickerVisibility {
    let id: String
    let hiddenReason: String?

    var hiddenByDefault: Bool { hiddenReason != nil }
}

struct SourcePickerPreferences: Codable, Equatable {
    struct Update {
        let id: String
        let isHidden: Bool
    }

    private var overrides: [String: Bool] = [:]

    init(encoded: String) {
        if let data = encoded.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            self = decoded
        }
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    func isHidden(_ source: SourcePickerVisibility) -> Bool {
        overrides[source.id] ?? source.hiddenByDefault
    }

    mutating func update(_ update: Update) {
        overrides[update.id] = update.isHidden
    }
}

enum CameraSourceKind {
    case builtIn
    case external
    case continuity
    case deskView

    var subtitle: String {
        switch self {
        case .builtIn: "Built into this Mac"
        case .external: "Connected to this Mac"
        case .continuity: "Apple Continuity Camera"
        case .deskView: "Apple Desk View"
        }
    }

    var systemImage: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .external: "web.camera"
        case .continuity: "iphone"
        case .deskView: "deskview"
        }
    }

    var hiddenReason: String? {
        switch self {
        case .continuity, .deskView: "Continuity and Desk View are tucked away by default"
        case .builtIn, .external: nil
        }
    }
}
