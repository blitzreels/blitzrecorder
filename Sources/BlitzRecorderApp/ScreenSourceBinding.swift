import AppKit
import CoreGraphics

struct SourceOption: Equatable {
    let id: String
    let name: String
    var cameraKind: CameraSourceKind? = nil
}

struct ScreenSourceBinding: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case display
        case application
        case window
    }

    var kind: Kind
    var displayID: String?
    var bundleIdentifier: String?
    var applicationName: String?
    var processID: Int32?
    var windowID: UInt32?
    var windowTitle: String?

    var id: String {
        switch kind {
        case .display:
            return "display:\(displayID ?? "auto")"
        case .application:
            return "application:\(bundleIdentifier ?? applicationName ?? "\(processID ?? 0)")"
        case .window:
            return "window:\(windowID.map(String.init) ?? "\(bundleIdentifier ?? ""):\(windowTitle ?? "")")"
        }
    }

    var displayName: String {
        switch kind {
        case .display:
            return "Display \(displayID ?? "Auto")"
        case .application:
            return applicationName ?? bundleIdentifier ?? "Application"
        case .window:
            if let applicationName, let windowTitle, !windowTitle.isEmpty {
                return "\(applicationName) - \(windowTitle)"
            }
            return windowTitle ?? applicationName ?? "Window"
        }
    }

    var isConcreteSelection: Bool {
        switch kind {
        case .display:
            return displayID != nil
        case .application, .window:
            return true
        }
    }

    static func display(id: String?, name: String? = nil) -> ScreenSourceBinding {
        ScreenSourceBinding(
            kind: .display,
            displayID: id,
            bundleIdentifier: nil,
            applicationName: name,
            processID: nil,
            windowID: nil,
            windowTitle: nil
        )
    }
}

struct ScreenSourceOption: Equatable, Identifiable {
    let binding: ScreenSourceBinding
    let title: String
    let subtitle: String
    let systemImage: String
    let icon: NSImage?
    var activityRank: Int = .max
    var pickerPlacement: ScreenSourcePickerPlacement = .standard

    var id: String { binding.id }

    static func == (lhs: ScreenSourceOption, rhs: ScreenSourceOption) -> Bool {
        lhs.binding == rhs.binding
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.systemImage == rhs.systemImage
            && lhs.activityRank == rhs.activityRank
            && lhs.pickerPlacement == rhs.pickerPlacement
    }
}

struct ScreenSourceGeometry: Equatable {
    var usesPickedContent: Bool
    var fillsSceneFrame: Bool
    var selectedDisplayID: String?
    var normalizedCrop: CGRect?
    var sourceAspectRatio: CGFloat?

    init(
        usesPickedContent: Bool = false,
        fillsSceneFrame: Bool = false,
        selectedDisplayID: String? = nil,
        normalizedCrop: CGRect? = nil,
        sourceAspectRatio: CGFloat? = nil
    ) {
        self.usesPickedContent = usesPickedContent
        self.fillsSceneFrame = fillsSceneFrame
        self.selectedDisplayID = selectedDisplayID
        self.normalizedCrop = normalizedCrop
        self.sourceAspectRatio = sourceAspectRatio
    }

    init(settings: RecordingSettings, sourceAspectRatio: CGFloat? = nil) {
        self.init(
            usesPickedContent: settings.usesPickedScreenContent,
            fillsSceneFrame: Self.fillsSceneFrame(for: settings),
            selectedDisplayID: settings.selectedDisplayID,
            normalizedCrop: ScreenCaptureGeometry.effectiveCrop(for: settings),
            sourceAspectRatio: sourceAspectRatio
        )
    }

    static func fillsSceneFrame(for settings: RecordingSettings) -> Bool {
        if settings.usesPickedScreenContent {
            return true
        }
        return settings.screenSourceBinding?.kind == .application
            || settings.screenSourceBinding?.kind == .window
    }

    func aspectRatio(fallback: CGFloat = SceneLayout.defaultScreenAspectRatio) -> CGFloat {
        if let sourceAspectRatio, sourceAspectRatio > 0 {
            return sourceAspectRatio
        }
        if let normalizedCrop, normalizedCrop.width > 0, normalizedCrop.height > 0 {
            return normalizedCrop.width / normalizedCrop.height
        }
        return fallback
    }

    func sourceRect(in rect: CGRect) -> CGRect {
        guard let normalizedCrop else { return rect }
        let crop = normalizedCrop.standardized
        let x = min(1, max(0, crop.minX))
        let y = min(1, max(0, crop.minY))
        let maxX = min(1, max(x, crop.maxX))
        let maxY = min(1, max(y, crop.maxY))
        return CGRect(
            x: rect.minX + x * rect.width,
            y: rect.minY + y * rect.height,
            width: max(2, (maxX - x) * rect.width),
            height: max(2, (maxY - y) * rect.height)
        )
    }
}

enum RecordingSourceSuggestion {
    struct Request {
        let current: ScreenSourceBinding?
        let candidate: ScreenSourceBinding
        let ownProcessID: Int32
    }

    static func shouldSuggest(_ request: Request) -> Bool {
        guard request.candidate.processID != request.ownProcessID,
            request.current?.kind != .display else { return false }
        if request.current?.kind == .application,
            request.current?.processID == request.candidate.processID { return false }
        return request.current?.id != request.candidate.id
    }
}
