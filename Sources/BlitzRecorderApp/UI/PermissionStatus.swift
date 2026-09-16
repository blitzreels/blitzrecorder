import Foundation

struct PermissionStatusRow: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let symbol: String
    let status: String
    let isActive: Bool
    let isBlocked: Bool
    let isOptional: Bool
    let source: CaptureSource?

    var isGranted: Bool {
        let grantedStatuses = [
            "allowed",
            "authorized",
            "remote iPhone",
            "selected source ready",
            "session access active",
            "full capture access active",
            "enabled for recordings"
        ]
        return grantedStatuses.contains(status) || status.hasPrefix("allowed for ")
    }

    var level: PermissionStatusLevel {
        if !isActive {
            return .inactive
        }
        if isGranted {
            return .granted
        }
        if status == "not determined" {
            return .warning
        }
        return isBlocked ? .blocked : .warning
    }
}

enum PermissionStatusLevel: Equatable {
    case inactive
    case granted
    case warning
    case blocked
}

enum PermissionStatusRows {
    struct Request {
        let settings: RecordingSettings
        let readiness: RecordingReadiness
        let hasPersistentScreenCaptureAccess: Bool
        let appName: String
        let hasAccessibilityAccess: Bool
        let status: (CaptureSource, Bool) -> String
    }

    static func make(_ request: Request) -> [PermissionStatusRow] {
        var rows = CaptureSource.allCases.map { source in
            let isActive = request.settings.enabledSources.contains(source)
            let isSelectedScreenAwaitingFullCaptureAccess = source == .screen
                && request.settings.screenSourceBinding?.isConcreteSelection == true
                && !request.settings.usesPickedScreenContent
                && !request.hasPersistentScreenCaptureAccess
            let isBlocked = request.readiness.blockers.contains { $0.source == source }
            let status: String
            if !isActive {
                status = "not used by current setup"
            } else {
                status = request.status(source, isBlocked)
            }
            return PermissionStatusRow(
                title: source.rawValue,
                symbol: source.symbolName,
                status: status,
                isActive: isActive,
                isBlocked: isBlocked && !isSelectedScreenAwaitingFullCaptureAccess,
                isOptional: false,
                source: source
            )
        }
        rows.append(PermissionStatusRow(
            title: "Accessibility",
            symbol: "accessibility",
            status: request.hasAccessibilityAccess ? "allowed" : "optional for target-window controls",
            isActive: request.hasAccessibilityAccess,
            isBlocked: false,
            isOptional: true,
            source: nil
        ))
        return rows
    }

    static func actionTitle(blockers: [PermissionBlocker]) -> String {
        switch PermissionPrimaryAction.resolve(blockers: blockers) {
        case .requestAccess:
            return "Request Access"
        case .openSettings:
            return "Open Settings"
        case .checkAccess:
            return "Check Access"
        }
    }

    static func setupSummary(readiness: RecordingReadiness, enabledSourcesEmpty: Bool) -> String {
        if readiness.isReady {
            return "All selected sources are ready."
        }
        if enabledSourcesEmpty {
            return "Choose at least one source before recording."
        }
        return readiness.blockers.first?.sentence ?? readiness.detail
    }
}

enum PermissionPrimaryAction: Equatable {
    case requestAccess
    case openSettings
    case checkAccess

    static func resolve(blockers: [PermissionBlocker]) -> Self {
        if blockers.contains(where: { $0.source == .camera || $0.source == .microphone }) {
            return .requestAccess
        }
        if blockers.contains(where: { $0.source == .screen || $0.source == .systemAudio }) {
            return .openSettings
        }
        return .checkAccess
    }
}
