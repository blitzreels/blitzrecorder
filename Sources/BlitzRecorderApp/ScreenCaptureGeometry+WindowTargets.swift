import AppKit
import CoreGraphics
import ScreenCaptureKit

extension ScreenCaptureGeometry {
    static func pickedWindowTarget(for filter: SCContentFilter) async -> PickedWindowTarget? {
        let contentRect = SCShareableContent.info(for: filter).contentRect
        guard contentRect.width > 0, contentRect.height > 0 else {
            return nil
        }

        guard let content = try? await SCShareableContent.currentProcess else {
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
        if let target = knownWindowTarget(binding) { return target }
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

    static func knownWindowTarget(_ binding: ScreenSourceBinding) -> PickedWindowTarget? {
        guard let identity = ScreenWindowIdentity(binding),
              let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, identity.windowID) as? [[String: Any]],
              let info = windows.first,
              let windowID = info[kCGWindowNumber as String] as? UInt32,
              let pid = info[kCGWindowOwnerPID as String] as? Int32,
              let application = NSRunningApplication(processIdentifier: pid),
              identity.matches(.init(windowID: windowID, processID: pid, bundleIdentifier: application.bundleIdentifier)),
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              frame.width > 0, frame.height > 0 else { return nil }
        return PickedWindowTarget(
            pid: pid,
            bounds: frame,
            title: info[kCGWindowName as String] as? String ?? binding.windowTitle,
            appName: application.localizedName,
            displayID: binding.displayID
        )
    }

    static func applicationWindowTarget(for binding: ScreenSourceBinding) async -> PickedWindowTarget? {
        guard binding.kind == .application,
              let content = try? await SCShareableContent.current,
              let application = application(matching: binding, in: content) else {
            return nil
        }

        let targetDisplay = display(from: content.displays, id: binding.displayID)
        guard let window = primaryWindow(
            for: application,
            on: targetDisplay,
            in: content
        ),
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

    static func displayID(for window: SCWindow, displays: [SCDisplay]) -> String? {
        displays
            .max { lhs, rhs in
                overlapArea(lhs.frame, window.frame) < overlapArea(rhs.frame, window.frame)
            }
            .map { String($0.displayID) }
    }

    static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func applicationWindowScore(_ window: SCWindow, displayFrame: CGRect?) -> CGFloat {
        let area = window.frame.width * window.frame.height
        guard let displayFrame else { return area }
        return overlapArea(window.frame, displayFrame)
    }

    static func application(
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

    static func window(matching binding: ScreenSourceBinding?, in content: SCShareableContent) -> SCWindow? {
        guard let binding, let identity = ScreenWindowIdentity(binding) else { return nil }
        return content.windows.first { window in
            guard window.isOnScreen, window.frame.width > 0, window.frame.height > 0 else { return false }
            return identity.matches(.init(
                windowID: window.windowID,
                processID: window.owningApplication?.processID,
                bundleIdentifier: window.owningApplication?.bundleIdentifier
            ))
        }
    }

    static func primaryWindow(
        for application: SCRunningApplication,
        on display: SCDisplay?,
        in content: SCShareableContent
    ) -> SCWindow? {
        let displayFrame = display?.frame
        let appWindows = content.windows
            .filter { window in
                window.isOnScreen
                    && window.frame.width > 0
                    && window.frame.height > 0
                    && windowBelongs(window, to: application)
                    && displayFrame.map { !window.frame.intersection($0).isNull } != false
            }
        return appWindows.max { lhs, rhs in
            let lhsScore = applicationWindowScore(lhs, displayFrame: displayFrame)
            let rhsScore = applicationWindowScore(rhs, displayFrame: displayFrame)
            return lhsScore < rhsScore
        }
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
}
