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
    let filter: SCContentFilter
    let geometry: ScreenSourceGeometry
    let sourceRect: CGRect?
    let display: SCDisplay?
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
                filter: filter,
                geometry: screenSourceGeometry(for: settings, pickedFilter: filter),
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
            let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
            let sourceRect = applicationSourceRect(
                for: application,
                on: display,
                in: content
            )
            let sourceAspectRatio = sourceRect.map { $0.width / max(1, $0.height) }
                ?? pickedContentAspectRatio(for: filter)
            return ResolvedScreenSource(
                filter: filter,
                geometry: ScreenSourceGeometry(
                    usesPickedContent: true,
                    selectedDisplayID: String(display.displayID),
                    normalizedCrop: nil,
                    sourceAspectRatio: sourceAspectRatio
                ),
                sourceRect: sourceRect,
                display: display
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
                filter: filter,
                geometry: geometry,
                sourceRect: geometry.sourceRect(in: CGRect(x: 0, y: 0, width: display.width, height: display.height)),
                display: display
            )
        }
    }

    static func screenSourceGeometry(for settings: RecordingSettings) -> ScreenSourceGeometry {
        ScreenSourceGeometry(settings: settings)
    }

    static func screenSourceGeometry(for settings: RecordingSettings, display: SCDisplay) -> ScreenSourceGeometry {
        ScreenSourceGeometry(
            usesPickedContent: false,
            selectedDisplayID: String(display.displayID),
            normalizedCrop: settings.screenCrop,
            sourceAspectRatio: screenSourceAspectRatio(
                for: settings,
                fallback: aspectRatio(width: display.width, height: display.height)
            )
        )
    }

    static func screenSourceGeometry(for settings: RecordingSettings, pickedFilter: SCContentFilter) -> ScreenSourceGeometry {
        ScreenSourceGeometry(
            usesPickedContent: true,
            selectedDisplayID: settings.selectedDisplayID,
            normalizedCrop: nil,
            sourceAspectRatio: pickedContentAspectRatio(for: pickedFilter)
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

    private static func pickedDisplay(for contentRect: CGRect, displays: [SCDisplay]) -> SCDisplay? {
        displays
            .filter { display in
                abs(display.frame.width - contentRect.width) < 2
                    && abs(display.frame.height - contentRect.height) < 2
            }
            .max {
                overlapArea($0.frame, contentRect) < overlapArea($1.frame, contentRect)
            }
    }

    static func outputDimensions(for settings: RecordingSettings) -> (width: Int, height: Int) {
        settings.outputResolution.dimensions(for: settings.layout)
    }

    static func screenCaptureDimensions(for settings: RecordingSettings) -> (width: Int, height: Int) {
        screenCaptureDimensions(for: settings, sourceAspectRatio: settings.layout.aspectRatio)
    }

    static func screenCaptureDimensions(
        for settings: RecordingSettings,
        pickedFilter: SCContentFilter
    ) -> (width: Int, height: Int) {
        screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: pickedContentAspectRatio(for: pickedFilter)
        )
    }

    static func screenCaptureDimensions(
        for settings: RecordingSettings,
        display: SCDisplay
    ) -> (width: Int, height: Int) {
        screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: screenSourceAspectRatio(
                for: settings,
                fallback: aspectRatio(width: display.width, height: display.height)
            )
        )
    }

    static func screenCaptureDimensions(
        for settings: RecordingSettings,
        sourceAspectRatio: CGFloat
    ) -> (width: Int, height: Int) {
        let sourceAspectRatio = max(0.1, sourceAspectRatio)
        let shortEdge = CGFloat(settings.outputResolution.height)
        let dimensions: (width: Int, height: Int)
        if sourceAspectRatio >= 1 {
            dimensions = (
                width: evenDimension(Int((shortEdge * sourceAspectRatio).rounded())),
                height: evenDimension(Int(shortEdge.rounded()))
            )
        } else {
            dimensions = (
                width: evenDimension(Int(shortEdge.rounded())),
                height: evenDimension(Int((shortEdge / sourceAspectRatio).rounded()))
            )
        }
        return dimensions
    }

    static func previewDimensions(for layout: CaptureLayout) -> (width: Int, height: Int) {
        switch layout {
        case .vertical:
            return (720, 1280)
        case .horizontal:
            return (1280, 720)
        }
    }

    static func previewDimensions(for display: SCDisplay) -> (width: Int, height: Int) {
        dimensions(forAspectRatio: aspectRatio(width: display.width, height: display.height), longEdge: 1280)
    }

    static func previewDimensions(for display: SCDisplay, settings: RecordingSettings) -> (width: Int, height: Int) {
        dimensions(
            forAspectRatio: screenSourceGeometry(for: settings, display: display).aspectRatio(),
            longEdge: 1280
        )
    }

    static func previewDimensions(for pickedFilter: SCContentFilter) -> (width: Int, height: Int) {
        dimensions(forAspectRatio: pickedContentAspectRatio(for: pickedFilter), longEdge: 1280)
    }

    static func previewDimensions(forSourceAspectRatio sourceAspectRatio: CGFloat) -> (width: Int, height: Int) {
        dimensions(forAspectRatio: sourceAspectRatio, longEdge: 1280)
    }

    static func sourceRect(for display: SCDisplay, settings: RecordingSettings) -> CGRect {
        let fullRect = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        return screenSourceGeometry(for: settings, display: display).sourceRect(in: fullRect)
    }

    static func sourceRect(for display: SCDisplay, layout: CaptureLayout) -> CGRect {
        CGRect(x: 0, y: 0, width: display.width, height: display.height)
    }

    static func screenSourceAspectRatio(for settings: RecordingSettings, fallback: CGFloat) -> CGFloat {
        if let screenCrop = settings.screenCrop, screenCrop.width > 0, screenCrop.height > 0 {
            return screenCrop.width / screenCrop.height
        }
        return fallback
    }

    static func pickedContentAspectRatio(for filter: SCContentFilter) -> CGFloat {
        let rect = SCShareableContent.info(for: filter).contentRect
        guard rect.width > 0, rect.height > 0 else {
            return SceneLayout.defaultScreenAspectRatio
        }
        return rect.width / rect.height
    }

    static func persistentBinding(forPickedContent filter: SCContentFilter) async -> ScreenSourceBinding? {
        let contentRect = SCShareableContent.info(for: filter).contentRect
        guard contentRect.width > 0, contentRect.height > 0,
              let content = try? await SCShareableContent.current else {
            return nil
        }

        if let display = pickedDisplay(for: contentRect, displays: content.displays) {
            return .display(
                id: String(display.displayID),
                name: "Display \(display.displayID) (\(display.width)x\(display.height))"
            )
        }

        let overlappingWindows = content.windows
            .filter { window in
                window.isOnScreen
                    && window.frame.width > 0
                    && window.frame.height > 0
                    && overlapArea(window.frame, contentRect) > 0
            }
            .sorted { lhs, rhs in
                overlapArea(lhs.frame, contentRect) > overlapArea(rhs.frame, contentRect)
            }

        guard let target = overlappingWindows.first,
              let app = target.owningApplication else {
            return nil
        }

        let targetOverlap = overlapArea(target.frame, contentRect)
        let significantWindows = overlappingWindows.filter { window in
            overlapArea(window.frame, contentRect) >= max(1, targetOverlap * 0.2)
        }
        if significantWindows.count > 1,
           significantWindows.allSatisfy({ windowBelongs($0, to: app) }) {
            return ScreenSourceBinding(
                kind: .application,
                displayID: displayID(for: target, displays: content.displays),
                bundleIdentifier: app.bundleIdentifier,
                applicationName: app.applicationName,
                processID: app.processID,
                windowID: nil,
                windowTitle: nil
            )
        }

        return ScreenSourceBinding(
            kind: .window,
            displayID: displayID(for: target, displays: content.displays),
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.applicationName,
            processID: app.processID,
            windowID: target.windowID,
            windowTitle: target.title
        )
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

    static func pickedWindowTarget(for filter: SCContentFilter) async -> PickedWindowTarget? {
        let contentRect = SCShareableContent.info(for: filter).contentRect
        guard contentRect.width > 0, contentRect.height > 0,
              let content = try? await SCShareableContent.current else {
            return nil
        }

        let matchesDisplay = content.displays.contains { display in
            abs(display.frame.width - contentRect.width) < 2
                && abs(display.frame.height - contentRect.height) < 2
        }
        if matchesDisplay { return nil }

        let target = content.windows
            .filter { $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0 }
            .max { overlapArea($0.frame, contentRect) < overlapArea($1.frame, contentRect) }

        guard let window = target,
              overlapArea(window.frame, contentRect) > 0,
              let pid = window.owningApplication?.processID else {
            return nil
        }

        return PickedWindowTarget(
            pid: pid,
            bounds: window.frame,
            title: window.title,
            appName: window.owningApplication?.applicationName,
            displayID: displayID(for: window, displays: content.displays)
        )
    }

    static func windowTarget(for binding: ScreenSourceBinding) async -> PickedWindowTarget? {
        guard let content = try? await SCShareableContent.current else { return nil }
        guard let window = window(matching: binding, in: content),
              let pid = window.owningApplication?.processID else {
            return nil
        }
        return PickedWindowTarget(
            pid: pid,
            bounds: window.frame,
            title: window.title,
            appName: window.owningApplication?.applicationName,
            displayID: binding.displayID ?? displayID(for: window, displays: content.displays)
        )
    }

    static func applicationWindowTarget(for binding: ScreenSourceBinding) async -> PickedWindowTarget? {
        guard binding.kind == .application,
              let content = try? await SCShareableContent.current,
              let application = application(matching: binding, in: content) else {
            return nil
        }

        let targetDisplay = display(from: content.displays, id: binding.displayID)
        let displayFrame = targetDisplay?.frame
        let appWindows = content.windows.filter { window in
            window.isOnScreen
                && window.frame.width > 0
                && window.frame.height > 0
                && windowBelongs(window, to: application)
                && displayFrame.map { !window.frame.intersection($0).isNull } != false
        }

        let target = appWindows.max { lhs, rhs in
            let lhsScore = applicationWindowScore(lhs, displayFrame: displayFrame)
            let rhsScore = applicationWindowScore(rhs, displayFrame: displayFrame)
            return lhsScore < rhsScore
        }

        guard let window = target,
              let pid = window.owningApplication?.processID else {
            return nil
        }

        return PickedWindowTarget(
            pid: pid,
            bounds: window.frame,
            title: window.title,
            appName: window.owningApplication?.applicationName,
            displayID: binding.displayID ?? displayID(for: window, displays: content.displays)
        )
    }

    private static func displayID(for window: SCWindow, displays: [SCDisplay]) -> String? {
        displays
            .max { lhs, rhs in
                overlapArea(lhs.frame, window.frame) < overlapArea(rhs.frame, window.frame)
            }
            .map { String($0.displayID) }
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func applicationWindowScore(_ window: SCWindow, displayFrame: CGRect?) -> CGFloat {
        let area = window.frame.width * window.frame.height
        guard let displayFrame else { return area }
        return overlapArea(window.frame, displayFrame)
    }

    private static func application(
        matching binding: ScreenSourceBinding?,
        in content: SCShareableContent
    ) -> SCRunningApplication? {
        guard let binding else { return nil }
        if let bundleIdentifier = binding.bundleIdentifier,
           let app = content.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return app
        }
        if let processID = binding.processID,
           let app = content.applications.first(where: { $0.processID == processID }) {
            return app
        }
        if let applicationName = binding.applicationName {
            return content.applications.first(where: { $0.applicationName == applicationName })
        }
        return nil
    }

    private static func window(matching binding: ScreenSourceBinding?, in content: SCShareableContent) -> SCWindow? {
        guard let binding else { return nil }
        let windows = content.windows.filter { $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0 }
        if let windowID = binding.windowID,
           let window = windows.first(where: { $0.windowID == windowID }) {
            return window
        }
        let matchingWindows = windows.filter { window in
            let bundleMatches = binding.bundleIdentifier == nil
                || window.owningApplication?.bundleIdentifier == binding.bundleIdentifier
            let titleMatches = binding.windowTitle == nil || window.title == binding.windowTitle
            return bundleMatches && titleMatches
        }

        if let processID = binding.processID,
           let processMatch = matchingWindows
            .filter({ $0.owningApplication?.processID == processID })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            return processMatch
        }

        return matchingWindows.max {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }
    }

    private static func applicationSourceRect(
        for application: SCRunningApplication,
        on display: SCDisplay,
        in content: SCShareableContent
    ) -> CGRect? {
        let appWindows = content.windows
            .filter { window in
                window.isOnScreen
                    && window.frame.width > 0
                    && window.frame.height > 0
                    && windowBelongs(window, to: application)
                    && !window.frame.intersection(display.frame).isNull
            }
            .map(\.frame)

        guard let union = appWindows.reduce(nil, { partial, frame -> CGRect? in
            partial.map { $0.union(frame) } ?? frame
        }) else {
            return nil
        }

        return displayLocalSourceRect(
            for: union,
            displayFrame: display.frame,
            displayPixelSize: CGSize(width: display.width, height: display.height)
        )
    }

    private static func windowBelongs(_ window: SCWindow, to application: SCRunningApplication) -> Bool {
        guard let owningApplication = window.owningApplication else { return false }
        if owningApplication.processID == application.processID {
            return true
        }
        if owningApplication.bundleIdentifier == application.bundleIdentifier {
            return true
        }
        return owningApplication.applicationName == application.applicationName
    }

    private static func dimensions(forAspectRatio aspectRatio: CGFloat, longEdge: Int) -> (width: Int, height: Int) {
        let aspectRatio = max(0.1, aspectRatio)
        if aspectRatio >= 1 {
            return (
                width: evenDimension(longEdge),
                height: evenDimension(Int((CGFloat(longEdge) / aspectRatio).rounded()))
            )
        }

        return (
            width: evenDimension(Int((CGFloat(longEdge) * aspectRatio).rounded())),
            height: evenDimension(longEdge)
        )
    }

    private static func aspectRatio(width: Int, height: Int) -> CGFloat {
        guard height > 0 else { return SceneLayout.defaultScreenAspectRatio }
        return CGFloat(width) / CGFloat(height)
    }

    private static func evenDimension(_ value: Int) -> Int {
        let value = max(2, value)
        return value.isMultiple(of: 2) ? value : value + 1
    }
}
