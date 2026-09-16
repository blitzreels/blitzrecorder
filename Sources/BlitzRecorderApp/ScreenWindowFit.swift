import AppKit
import Foundation
import ScreenCaptureKit

enum ScreenWindowFit {
    struct ArrangementRequest {
        let binding: ScreenSourceBinding
        let zoom: CGFloat
        let fallbackDisplayID: String?
        let captureLayout: CaptureLayout
        let sceneLayout: SceneLayout
        let enabledSources: Set<CaptureSource>
        let canvasPadding: CGFloat
    }

    struct PickedArrangementRequest {
        let filter: SCContentFilter
        let binding: ScreenSourceBinding?
        let zoom: CGFloat
        let fallbackDisplayID: String?
        let captureLayout: CaptureLayout
        let sceneLayout: SceneLayout
        let enabledSources: Set<CaptureSource>
        let canvasPadding: CGFloat
    }

    static func applicationMatches(
        _ application: NSRunningApplication,
        binding: ScreenSourceBinding
    ) -> Bool {
        if let bundleIdentifier = binding.bundleIdentifier,
           application.bundleIdentifier != bundleIdentifier {
            return false
        }
        if let applicationName = binding.applicationName,
           let localizedName = application.localizedName,
           localizedName != applicationName {
            return false
        }
        return true
    }

    static func processID(forApplicationBinding binding: ScreenSourceBinding) -> pid_t? {
        if let processID = binding.processID,
           let application = NSRunningApplication(processIdentifier: processID),
           applicationMatches(application, binding: binding) {
            return processID
        }
        if let bundleIdentifier = binding.bundleIdentifier {
            let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            return (applications.first(where: { $0.activationPolicy == .regular }) ?? applications.first)?
                .processIdentifier
        }
        if let applicationName = binding.applicationName {
            return NSWorkspace.shared.runningApplications
                .first { $0.localizedName == applicationName && $0.activationPolicy == .regular }?
                .processIdentifier
        }
        return nil
    }

    static func arrangement(
        _ request: ArrangementRequest,
        isCurrent: () -> Bool
    ) async throws -> ShortsWindowArrangement? {
        let displayID = request.binding.displayID ?? request.fallbackDisplayID
        if request.binding.kind == .application {
            if let target = await ScreenCaptureGeometry.applicationWindowTarget(for: request.binding) {
                guard isCurrent() else { return nil }
                return try await ShortsWindowArranger.fitWindow(
                    ownerPID: target.pid,
                    bounds: target.bounds,
                    title: target.title,
                    appName: target.appName ?? request.binding.applicationName ?? "Application",
                    displayID: target.displayID ?? displayID,
                    captureLayout: request.captureLayout,
                    sceneLayout: request.sceneLayout,
                    enabledSources: request.enabledSources,
                    canvasPadding: request.canvasPadding,
                    zoom: request.zoom
                )
            }

            if let processID = processID(forApplicationBinding: request.binding) {
                guard isCurrent() else { return nil }
                return try await ShortsWindowArranger.fitAppWindow(
                    ownerPID: processID,
                    appName: request.binding.applicationName ?? "Application",
                    displayID: displayID,
                    captureLayout: request.captureLayout,
                    sceneLayout: request.sceneLayout,
                    enabledSources: request.enabledSources,
                    canvasPadding: request.canvasPadding,
                    zoom: request.zoom
                )
            }
        }

        guard let target = await ScreenCaptureGeometry.windowTarget(for: request.binding) else {
            throw ShortsWindowArrangerError.noWindowFound
        }
        guard isCurrent() else { return nil }

        return try await ShortsWindowArranger.fitWindow(
            ownerPID: target.pid,
            bounds: target.bounds,
            title: target.title,
            appName: target.appName ?? "",
            displayID: target.displayID ?? displayID,
            captureLayout: request.captureLayout,
            sceneLayout: request.sceneLayout,
            enabledSources: request.enabledSources,
            canvasPadding: request.canvasPadding,
            zoom: request.zoom
        )
    }

    static func pickedArrangement(
        _ request: PickedArrangementRequest,
        isCurrent: () -> Bool
    ) async throws -> ShortsWindowArrangement {
        let displayID = request.binding?.displayID ?? request.fallbackDisplayID
        if let binding = request.binding,
           let processID = binding.processID,
           binding.kind == .window {
            guard isCurrent() else { throw CancellationError() }
            return try await ShortsWindowArranger.fitWindow(
                ownerPID: processID,
                bounds: request.filter.contentRect,
                title: binding.windowTitle,
                appName: binding.applicationName ?? "Application",
                displayID: displayID,
                captureLayout: request.captureLayout,
                sceneLayout: request.sceneLayout,
                enabledSources: request.enabledSources,
                canvasPadding: request.canvasPadding,
                zoom: request.zoom
            )
        }
        if let binding = request.binding,
           let processID = binding.processID,
           binding.kind == .application {
            guard isCurrent() else { throw CancellationError() }
            return try await ShortsWindowArranger.fitAppWindow(
                ownerPID: processID,
                appName: binding.applicationName ?? "Application",
                displayID: displayID,
                captureLayout: request.captureLayout,
                sceneLayout: request.sceneLayout,
                enabledSources: request.enabledSources,
                canvasPadding: request.canvasPadding,
                zoom: request.zoom
            )
        }
        guard let target = await ScreenCaptureGeometry.pickedWindowTarget(for: request.filter) else {
            throw ShortsWindowArrangerError.noWindowFound
        }
        guard isCurrent() else { throw CancellationError() }
        return try await ShortsWindowArranger.fitWindow(
            ownerPID: target.pid,
            bounds: target.bounds,
            title: target.title,
            appName: target.appName ?? "",
            displayID: target.displayID ?? displayID,
            captureLayout: request.captureLayout,
            sceneLayout: request.sceneLayout,
            enabledSources: request.enabledSources,
            canvasPadding: request.canvasPadding,
            zoom: request.zoom
        )
    }

    struct ScalingSupportRequest {
        let settings: RecordingSettings
        let hasActivePickerSelection: Bool
        let activePickedKind: ScreenSourceBinding.Kind?
    }

    static func supportsScaling(_ request: ScalingSupportRequest) -> Bool {
        if request.activePickedKind == .display {
            return false
        }
        switch request.settings.screenSourceBinding?.kind {
        case .application, .window:
            return true
        case .display:
            return false
        case nil:
            return request.settings.usesPickedScreenContent
                && request.hasActivePickerSelection
        }
    }

    struct FitControlsRequest {
        let settings: RecordingSettings
        let targetWindowInfo: TargetWindowInfo?
        let hasAccessibilityAccess: Bool
        let canAdjustScreenCapture: Bool
    }

    static func canShowFitControls(_ request: FitControlsRequest) -> Bool {
        guard request.canAdjustScreenCapture,
              request.hasAccessibilityAccess,
              request.settings.visibleSources.contains(.screen) else {
            return false
        }

        if request.settings.usesPickedScreenContent,
           request.settings.screenSourceBinding == nil {
            return true
        }

        switch request.settings.screenSourceBinding?.kind {
        case .window, .application:
            return true
        case .display, .none:
            return false
        }
    }

    enum RecordingStartPlan: Equatable {
        case picked
        case binding(ScreenSourceBinding)
        case skip

        static func make(
            visibleScreen: Bool,
            hasAccessibility: Bool,
            usesPickedScreenContent: Bool,
            pickedKind: ScreenSourceBinding.Kind?,
            binding: ScreenSourceBinding?
        ) -> Self {
            guard visibleScreen, hasAccessibility else { return .skip }
            if usesPickedScreenContent {
                guard pickedKind == .application || pickedKind == .window else { return .skip }
                return .picked
            }
            guard let binding, binding.kind != .display else { return .skip }
            return .binding(binding)
        }
    }
}
