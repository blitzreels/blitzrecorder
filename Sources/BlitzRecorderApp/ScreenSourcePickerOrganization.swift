import Foundation

enum ScreenSourcePickerPlacement: Equatable {
    case suggested(rank: Int)
    case standard
    case sensitive
    case utility

    var group: ScreenSourcePickerGroup {
        switch self {
        case .suggested:
            return .suggested
        case .standard:
            return .standard
        case .utility:
            return .utility
        case .sensitive:
            return .sensitive
        }
    }

    var sortRank: Int {
        switch self {
        case .suggested(let rank):
            return rank
        case .standard:
            return 1_000
        case .utility:
            return 3_000
        case .sensitive:
            return 2_000
        }
    }
}

enum ScreenSourcePickerGroup {
    case all
    case suggested
    case standard
    case sensitive
    case utility
}

struct ScreenSourcePickerPlacementRequest {
    let binding: ScreenSourceBinding
    let recentBundleIdentifiers: [String]
}

struct ScreenSourcePickerRecentUpdateRequest {
    let bundleIdentifier: String?
    let existingBundleIdentifiers: [String]
}

enum ScreenSourcePickerOrganization {
    struct SelectionRequest {
        let selectedBinding: ScreenSourceBinding?
        let candidate: ScreenSourceBinding
        let usesPickedContent: Bool
    }

    static func isSelected(_ request: SelectionRequest) -> Bool {
        guard !request.usesPickedContent, let selected = request.selectedBinding else { return false }
        if selected.kind == .window {
            guard let identity = ScreenWindowIdentity(selected),
                  let candidate = ScreenWindowIdentity(request.candidate) else { return false }
            return identity.matches(candidate)
        }
        return selected.id == request.candidate.id
    }

    struct WindowVisibilityRequest {
        let size: CGSize
        let layer: Int
        let isSystemWindow: Bool
    }

    static func isUtilityWindow(_ request: WindowVisibilityRequest) -> Bool {
        request.size.width < 100 || request.size.height < 100 || request.layer != 0 || request.isSystemWindow
    }

    static func visibility(_ option: ScreenSourceOption) -> SourcePickerVisibility {
        let binding = option.binding
        let identity: String
        switch binding.kind {
        case .display: identity = binding.displayID ?? binding.id
        case .application: identity = binding.bundleIdentifier ?? binding.applicationName ?? binding.id
        case .window:
            identity = "\(binding.bundleIdentifier ?? binding.applicationName ?? "unknown"):\(binding.windowTitle ?? binding.id)"
        }
        let reason: String?
        switch option.pickerPlacement {
        case .sensitive: reason = "Private app"
        case .utility: reason = "Small or utility window"
        case .standard, .suggested: reason = nil
        }
        return SourcePickerVisibility(id: "screen:\(binding.kind.rawValue):\(identity)", hiddenReason: reason)
    }

    static let maximumRecentApplicationCount = 5

    private static let preferredBundleIdentifiers = [
        "com.google.chrome",
        "com.microsoft.vscode",
        "com.openai.codex"
    ]

    private static let sensitiveBundleIdentifierFragments = [
        "1password",
        "bitwarden",
        "dashlane",
        "enpass",
        "keepass",
        "keychainaccess",
        "lastpass",
        "passwords",
        "protonpass",
        "com.pais.handy"
    ]

    private static let sensitiveNameFragments = [
        "1password",
        "bitwarden",
        "dashlane",
        "enpass",
        "handy",
        "keepass",
        "keychain access",
        "lastpass",
        "passwords",
        "proton pass"
    ]

    static func placement(_ request: ScreenSourcePickerPlacementRequest) -> ScreenSourcePickerPlacement {
        if isSensitive(request.binding) {
            return .sensitive
        }
        guard request.binding.kind == .application else {
            return .standard
        }

        let normalizedRecentBundleIdentifiers = request.recentBundleIdentifiers.map { $0.lowercased() }
        if let bundleIdentifier = request.binding.bundleIdentifier?.lowercased(),
           let recentIndex = normalizedRecentBundleIdentifiers.firstIndex(of: bundleIdentifier) {
            return .suggested(rank: recentIndex)
        }
        if let bundleIdentifier = request.binding.bundleIdentifier?.lowercased(),
           let preferredIndex = preferredBundleIdentifiers.firstIndex(of: bundleIdentifier) {
            return .suggested(rank: 100 + preferredIndex)
        }
        return .standard
    }

    static func sorted(_ options: [ScreenSourceOption]) -> [ScreenSourceOption] {
        options.sorted { lhs, rhs in
            if lhs.pickerPlacement.sortRank != rhs.pickerPlacement.sortRank {
                return lhs.pickerPlacement.sortRank < rhs.pickerPlacement.sortRank
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func updatedRecentBundleIdentifiers(
        _ request: ScreenSourcePickerRecentUpdateRequest
    ) -> [String] {
        guard let bundleIdentifier = request.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return request.existingBundleIdentifiers
        }

        let withoutDuplicate = request.existingBundleIdentifiers.filter {
            $0.localizedCaseInsensitiveCompare(bundleIdentifier) != .orderedSame
        }
        return Array(([bundleIdentifier] + withoutDuplicate).prefix(maximumRecentApplicationCount))
    }

    private static func isSensitive(_ binding: ScreenSourceBinding) -> Bool {
        let bundleIdentifier = binding.bundleIdentifier?.lowercased() ?? ""
        if sensitiveBundleIdentifierFragments.contains(where: bundleIdentifier.contains) {
            return true
        }

        let applicationName = binding.applicationName?.lowercased() ?? ""
        return sensitiveNameFragments.contains(where: applicationName.contains)
    }
}

struct ScreenSourcePickerRecents {
    private static let key = "screenPicker.recentApplicationBundleIdentifiers.v1"

    let defaults: UserDefaults

    func bundleIdentifiers() -> [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func record(_ binding: ScreenSourceBinding?) {
        guard let binding,
              binding.kind == .application || binding.kind == .window else {
            return
        }
        let updated = ScreenSourcePickerOrganization.updatedRecentBundleIdentifiers(
            ScreenSourcePickerRecentUpdateRequest(
                bundleIdentifier: binding.bundleIdentifier,
                existingBundleIdentifiers: bundleIdentifiers()
            )
        )
        defaults.set(updated, forKey: Self.key)
    }
}
