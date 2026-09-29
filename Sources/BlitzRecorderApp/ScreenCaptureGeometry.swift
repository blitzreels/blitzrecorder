import AppKit
import CoreGraphics
import Darwin
import ScreenCaptureKit

struct PickedWindowTarget {
    let pid: pid_t
    let bounds: CGRect
    let title: String?
    let appName: String?
    let displayID: String?
}

struct ResolvedScreenSource {
    let binding: ScreenSourceBinding
    let filter: SCContentFilter
    let geometry: ScreenSourceGeometry
    let sourceRect: CGRect?
    let display: SCDisplay?
}

struct PickedScreenSourceRectRequest {
    let settings: RecordingSettings
    let filter: SCContentFilter
}

struct ScreenSourceCropRequest {
    let sourceRect: CGRect
    let normalizedCrop: CGRect?
}

enum ScreenCaptureGeometry {
    static func screenSource(for settings: RecordingSettings, content: SCShareableContent) throws -> ResolvedScreenSource {
        let binding = settings.screenSourceBinding

        switch binding?.kind {
        case .window:
            guard let window = window(matching: binding, in: content) else {
                throw RecorderError.screenSourceUnavailable(binding?.displayName ?? "Selected window")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return ResolvedScreenSource(
                binding: windowBinding(.init(window: window, displays: content.displays)),
                filter: filter,
                geometry: windowSourceGeometry(.init(settings: settings, bounds: window.frame)),
                sourceRect: nil,
                display: nil
            )

        case .application:
            guard let application = application(matching: binding, in: content) else {
                throw RecorderError.screenSourceUnavailable(binding?.displayName ?? "Selected app")
            }
            guard let display = display(from: content.displays, id: binding?.displayID)
                ?? display(from: content.displays, settings: settings) else {
                throw RecorderError.noDisplay
            }
            guard let window = primaryWindow(
                for: application,
                on: display,
                in: content
            ) else {
                throw RecorderError.screenSourceUnavailable(binding?.displayName ?? "Selected app")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return ResolvedScreenSource(
                binding: windowBinding(.init(window: window, displays: content.displays)),
                filter: filter,
                geometry: windowSourceGeometry(.init(settings: settings, bounds: window.frame)),
                sourceRect: nil,
                display: nil
            )

        case .display, nil:
            guard let display = display(from: content.displays, id: binding?.displayID)
                ?? display(from: content.displays, settings: settings) else {
                throw RecorderError.noDisplay
            }
            let ownProcess = getpid()
            let excludedApplications = content.applications.filter { $0.processID == ownProcess }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let geometry = screenSourceGeometry(for: settings, display: display)
            return ResolvedScreenSource(
                binding: .display(id: String(display.displayID)),
                filter: filter,
                geometry: geometry,
                sourceRect: geometry.sourceRect(in: CGRect(x: 0, y: 0, width: display.width, height: display.height)),
                display: display
            )
        }
    }

    private struct WindowBindingRequest {
        let window: SCWindow
        let displays: [SCDisplay]
    }

    private static func windowBinding(_ request: WindowBindingRequest) -> ScreenSourceBinding {
        let window = request.window
        return ScreenSourceBinding(
            kind: .window,
            displayID: displayID(for: window, displays: request.displays),
            bundleIdentifier: window.owningApplication?.bundleIdentifier,
            applicationName: window.owningApplication?.applicationName,
            processID: window.owningApplication?.processID,
            windowID: window.windowID,
            windowTitle: window.title
        )
    }

    struct WindowGeometryRequest {
        let settings: RecordingSettings
        let bounds: CGRect
    }

    static func windowSourceGeometry(_ request: WindowGeometryRequest) -> ScreenSourceGeometry {
        var settings = request.settings
        if request.bounds.width > 0, request.bounds.height > 0 {
            settings.screenSourceAspectRatio = request.bounds.width / request.bounds.height
        }
        return ScreenSourceGeometry(
            usesPickedContent: true,
            fillsSceneFrame: true,
            selectedDisplayID: settings.selectedDisplayID,
            normalizedCrop: effectiveCrop(for: settings),
            sourceAspectRatio: pickedScreenSourceAspectRatio(
                for: settings,
                fallback: SceneLayout.defaultScreenAspectRatio
            )
        )
    }

    static func screenSourceGeometry(for settings: RecordingSettings) -> ScreenSourceGeometry {
        ScreenSourceGeometry(settings: settings)
    }

    static func screenSourceGeometry(for settings: RecordingSettings, display: SCDisplay) -> ScreenSourceGeometry {
        ScreenSourceGeometry(
            usesPickedContent: false,
            fillsSceneFrame: ScreenSourceGeometry.fillsSceneFrame(for: settings),
            selectedDisplayID: String(display.displayID),
            normalizedCrop: effectiveCrop(for: settings),
            sourceAspectRatio: screenSourceAspectRatio(
                for: settings,
                fallback: aspectRatio(width: display.width, height: display.height)
            )
        )
    }

    static func screenSourceGeometry(for settings: RecordingSettings, pickedFilter: SCContentFilter) -> ScreenSourceGeometry {
        let fallbackAspectRatio = pickedContentAspectRatio(for: pickedFilter)
        return ScreenSourceGeometry(
            usesPickedContent: true,
            fillsSceneFrame: true,
            selectedDisplayID: settings.selectedDisplayID,
            normalizedCrop: effectiveCrop(for: settings),
            sourceAspectRatio: pickedScreenSourceAspectRatio(
                for: settings,
                fallback: fallbackAspectRatio
            )
        )
    }

    private static func pickedScreenSourceAspectRatio(for settings: RecordingSettings, fallback: CGFloat) -> CGFloat {
        let sourceAspectRatio: CGFloat
        switch settings.screenSourceBinding?.kind {
        case .application, .window:
            sourceAspectRatio = settings.screenSourceAspectRatio ?? fallback
        case .display, nil:
            sourceAspectRatio = fallback
        }

        guard let screenCrop = settings.screenCrop,
              screenCrop.width > 0,
              screenCrop.height > 0 else {
            return sourceAspectRatio
        }
        return sourceAspectRatio * screenCrop.width / screenCrop.height
    }

    static func screenSourceGeometryForTesting(settings: RecordingSettings, pickedContentAspectRatio: CGFloat) -> ScreenSourceGeometry {
        ScreenSourceGeometry(
            usesPickedContent: true,
            fillsSceneFrame: true,
            selectedDisplayID: settings.selectedDisplayID,
            normalizedCrop: effectiveCrop(for: settings),
            sourceAspectRatio: pickedScreenSourceAspectRatio(
                for: settings,
                fallback: pickedContentAspectRatio
            )
        )
    }

    static func display(from displays: [SCDisplay], settings: RecordingSettings) -> SCDisplay? {
        if let selectedDisplayID = settings.selectedDisplayID,
           let numericID = UInt32(selectedDisplayID),
           let display = displays.first(where: { $0.displayID == numericID }) {
            return display
        }
        return displays.first(where: { CGMainDisplayID() == $0.displayID }) ?? displays.first
    }

    static func display(from displays: [SCDisplay], id: String?) -> SCDisplay? {
        guard let id, let numericID = UInt32(id) else { return nil }
        return displays.first(where: { $0.displayID == numericID })
    }

    static func screenSourceAspectRatio(for settings: RecordingSettings, fallback: CGFloat) -> CGFloat {
        if let screenCrop = settings.screenCrop, screenCrop.width > 0, screenCrop.height > 0 {
            return screenCrop.width / screenCrop.height
        }
        return fallback
    }

    struct ResolvedSourceAspectRatioRequest {
        var isEditingScreenCrop: Bool
        var bindingKind: ScreenSourceBinding.Kind?
        var pickedAspectRatio: CGFloat?
        var usesPickedScreenContent: Bool
        var pickedFilterAspectRatio: CGFloat?
        var selectedDisplayID: String?
        var settings: RecordingSettings
    }

    static func resolvedSourceAspectRatio(_ request: ResolvedSourceAspectRatioRequest) -> CGFloat {
        if !request.isEditingScreenCrop,
           request.bindingKind != .display,
           let picked = request.pickedAspectRatio, picked > 0 {
            return picked
        }
        if request.usesPickedScreenContent && !request.isEditingScreenCrop {
            if let picked = request.pickedAspectRatio, picked > 0 {
                return picked
            }
            if let filterAspect = request.pickedFilterAspectRatio, filterAspect > 0 {
                return filterAspect
            }
            return SceneLayout.defaultScreenAspectRatio
        }
        return screenSourceAspectRatio(
            for: request.settings,
            fallback: displayPixelAspectRatio(selectedDisplayID: request.selectedDisplayID)
        )
    }

    static func displayPixelAspectRatio(selectedDisplayID: String?) -> CGFloat {
        let displayID: CGDirectDisplayID
        if let selectedDisplayID, let numericID = UInt32(selectedDisplayID) {
            displayID = numericID
        } else {
            displayID = CGMainDisplayID()
        }
        let width = CGDisplayPixelsWide(displayID)
        let height = CGDisplayPixelsHigh(displayID)
        guard width > 0, height > 0 else {
            return SceneLayout.defaultScreenAspectRatio
        }
        return CGFloat(width) / CGFloat(height)
    }

    static func isStalePickerQueuedRevision(_ queued: Int?, current: Int) -> Bool {
        queued.map { $0 != current } ?? false
    }

    static func effectiveCrop(for settings: RecordingSettings) -> CGRect? {
        settings.screenCrop
    }
}

extension RecordingScene {
    static func live(
        settings: RecordingSettings,
        pickedFilter: SCContentFilter?
    ) -> RecordingScene {
        var scene = RecordingScene(settings: settings)
        guard settings.enabledSources.contains(.screen), let pickedFilter else {
            return scene
        }
        var geometry = ScreenCaptureGeometry.screenSourceGeometry(
            for: settings,
            pickedFilter: pickedFilter
        )
        geometry.usesPickedContent = settings.usesPickedScreenContent
        geometry.fillsSceneFrame = ScreenSourceGeometry.fillsSceneFrame(for: settings)
        scene.screenSourceGeometry = geometry
        return scene
    }
}
