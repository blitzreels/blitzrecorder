import CoreGraphics
import ScreenCaptureKit

extension ScreenCaptureGeometry {
    static func pickedContentAspectRatio(for filter: SCContentFilter) -> CGFloat {
        let rect = SCShareableContent.info(for: filter).contentRect
        guard rect.width > 0, rect.height > 0 else {
            return SceneLayout.defaultScreenAspectRatio
        }
        return rect.width / rect.height
    }

    static func normalizedPickedFilter(_ filter: SCContentFilter) -> SCContentFilter {
        guard #available(macOS 15.2, *),
              filter.style == .window,
              filter.includedWindows.count == 1,
              let window = filter.includedWindows.first else {
            return filter
        }
        return SCContentFilter(desktopIndependentWindow: window)
    }

    struct RecorderVisibilityRequest {
        let filter: SCContentFilter
        let includesRecorderUI: Bool
    }

    static func applyingRecorderVisibility(_ request: RecorderVisibilityRequest) async -> SCContentFilter {
        let filter = request.filter
        guard #available(macOS 15.2, *),
              filter.style == .display,
              filter.includedApplications.isEmpty,
              let display = filter.includedDisplays.first,
              let content = try? await SCShareableContent.current else {
            return filter
        }
        let policy = RecorderUICapturePolicy(includesRecorderUI: request.includesRecorderUI)
        return SCContentFilter(
            display: content.displays.first { $0.displayID == display.displayID } ?? display,
            excludingApplications: content.applications.filter { policy.excludes(processID: $0.processID) },
            exceptingWindows: []
        )
    }

    static func pickedSourceRect(request: PickedScreenSourceRectRequest) -> CGRect? {
        if usesAutomaticFullWindowSourceRect(for: request.settings) {
            return nil
        }

        let contentRect = SCShareableContent.info(for: request.filter).contentRect
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: max(2, contentRect.width),
            height: max(2, contentRect.height)
        )
        return screenSourceGeometry(
            for: request.settings,
            pickedFilter: request.filter
        ).sourceRect(in: bounds)
    }

    static func usesAutomaticFullWindowSourceRect(for settings: RecordingSettings) -> Bool {
        guard settings.screenCrop == nil else { return false }
        switch settings.screenSourceBinding?.kind {
        case .application, .window:
            return true
        case .display, nil:
            return false
        }
    }

    static func croppedSourceRect(request: ScreenSourceCropRequest) -> CGRect {
        guard let normalizedCrop = request.normalizedCrop else { return request.sourceRect }
        return CGRect(
            x: request.sourceRect.minX + request.sourceRect.width * normalizedCrop.minX,
            y: request.sourceRect.minY + request.sourceRect.height * normalizedCrop.minY,
            width: request.sourceRect.width * normalizedCrop.width,
            height: request.sourceRect.height * normalizedCrop.height
        )
    }

    static func persistentBinding(forPickedContent filter: SCContentFilter) async -> ScreenSourceBinding? {
        if #available(macOS 15.2, *),
           let exactBinding = exactPersistentBinding(for: filter) {
            return exactBinding
        }
        return nil
    }

    @available(macOS 15.2, *)
    private static func exactPersistentBinding(
        for filter: SCContentFilter
    ) -> ScreenSourceBinding? {
        switch filter.style {
        case .window:
            guard filter.includedWindows.count == 1,
                  let window = filter.includedWindows.first,
                  let application = window.owningApplication else {
                return nil
            }
            return ScreenSourceBinding(
                kind: .window,
                displayID: filter.includedDisplays.first.map { String($0.displayID) },
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.applicationName,
                processID: application.processID,
                windowID: window.windowID,
                windowTitle: window.title
            )
        case .application:
            guard filter.includedApplications.count == 1,
                  let application = filter.includedApplications.first else {
                return nil
            }
            return ScreenSourceBinding(
                kind: .application,
                displayID: filter.includedDisplays.first.map { String($0.displayID) },
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.applicationName,
                processID: application.processID,
                windowID: nil,
                windowTitle: nil
            )
        case .display:
            guard filter.includedDisplays.count == 1,
                  let display = filter.includedDisplays.first else {
                return nil
            }
            return ScreenSourceBinding(
                kind: .display,
                displayID: String(display.displayID),
                bundleIdentifier: nil,
                applicationName: "Display \(display.displayID) (\(display.width)x\(display.height))",
                processID: nil,
                windowID: nil,
                windowTitle: nil
            )
        case .none:
            return nil
        @unknown default:
            return nil
        }
    }

    static func displayLocalSourceRect(
        for rect: CGRect,
        displayFrame: CGRect,
        displayPixelSize: CGSize
    ) -> CGRect? {
        guard displayFrame.width > 0,
              displayFrame.height > 0,
              displayPixelSize.width > 0,
              displayPixelSize.height > 0 else {
            return nil
        }
        let clipped = rect.intersection(displayFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return nil
        }
        let scaleX = displayPixelSize.width / displayFrame.width
        let scaleY = displayPixelSize.height / displayFrame.height
        return CGRect(
            x: (clipped.minX - displayFrame.minX) * scaleX,
            y: (clipped.minY - displayFrame.minY) * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        ).integral
    }
}
