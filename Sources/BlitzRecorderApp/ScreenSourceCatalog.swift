import AppKit
import Foundation
import ScreenCaptureKit

struct WindowSourceSelectionContext {
    let currentSource: ScreenSourceBinding
    let targetWindow: TargetWindowInfo?
    let availableSources: [ScreenSourceOption]
}

enum ScreenSourceCatalog {
    static func options(
        content: SCShareableContent,
        recentBundleIdentifiers: [String],
        ownProcessID: pid_t = getpid()
    ) -> [ScreenSourceOption] {
        let visibleWindows = content.windows.filter {
            $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0
        }
        let primaryWindows = Dictionary(grouping: visibleWindows) { $0.owningApplication?.processID }
            .compactMapValues { windows in
                windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            }
        var applicationIcons: [pid_t: NSImage] = [:]
        for application in content.applications {
            guard application.processID != ownProcessID, primaryWindows[application.processID] != nil else { continue }
            applicationIcons[application.processID] = appIcon(
                bundleIdentifier: application.bundleIdentifier,
                processID: application.processID
            )
        }
        let displayOptions = content.displays.enumerated().map { index, display in
            ScreenSourceOption(
                binding: .display(id: String(display.displayID)),
                title: "Display \(index + 1)",
                subtitle: "\(display.width) × \(display.height)",
                systemImage: "display",
                icon: nil
            )
        }
        var applicationKeys: Set<String> = []
        let applicationOptions = content.applications.compactMap { application -> ScreenSourceOption? in
            let applicationName = readableApplicationName(application.applicationName)
            guard application.processID != ownProcessID,
                  let applicationName else {
                return nil
            }
            let key = applicationKey(
                bundleIdentifier: application.bundleIdentifier,
                processID: application.processID,
                applicationName: applicationName
            )
            guard applicationKeys.insert(key).inserted else { return nil }
            guard let primaryWindow = primaryWindows[application.processID] else { return nil }
            let isUtility = ScreenSourcePickerOrganization.isUtilityWindow(.init(
                size: primaryWindow.frame.size,
                layer: primaryWindow.windowLayer,
                isSystemWindow: isIgnoredWindow(
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: applicationName,
                    title: primaryWindow.title
                )
            ))
            let binding = ScreenSourceBinding(
                kind: .application,
                displayID: ScreenCaptureGeometry.displayID(for: primaryWindow, displays: content.displays),
                bundleIdentifier: application.bundleIdentifier,
                applicationName: applicationName,
                processID: application.processID,
                windowID: nil,
                windowTitle: nil
            )
            return ScreenSourceOption(
                binding: binding,
                title: applicationName,
                subtitle: readableWindowTitle(primaryWindow.title) ?? "Main window",
                systemImage: "macwindow.on.rectangle",
                icon: applicationIcons[application.processID],
                pickerPlacement: isUtility ? .utility : ScreenSourcePickerOrganization.placement(
                    ScreenSourcePickerPlacementRequest(
                        binding: binding,
                        recentBundleIdentifiers: recentBundleIdentifiers
                    )
                )
            )
        }
        let sortedApplicationOptions = ScreenSourcePickerOrganization.sorted(applicationOptions)

        let windowOptions = visibleWindows.compactMap { window -> ScreenSourceOption? in
            let application = window.owningApplication
            let applicationName = readableApplicationName(application?.applicationName)
            guard application?.processID != ownProcessID else {
                return nil
            }
            let isUtility = ScreenSourcePickerOrganization.isUtilityWindow(.init(
                size: window.frame.size,
                layer: window.windowLayer,
                isSystemWindow: isIgnoredWindow(
                    bundleIdentifier: application?.bundleIdentifier,
                    applicationName: applicationName,
                    title: window.title
                )
            ))
            let windowTitle = readableWindowTitle(window.title)
            let title = windowTitle ?? applicationName.map { "\($0) window" } ?? "Window"
            let binding = ScreenSourceBinding(
                kind: .window,
                displayID: ScreenCaptureGeometry.displayID(for: window, displays: content.displays),
                bundleIdentifier: application?.bundleIdentifier,
                applicationName: applicationName,
                processID: application?.processID,
                windowID: window.windowID,
                windowTitle: window.title
            )
            return ScreenSourceOption(
                binding: binding,
                title: title,
                subtitle: applicationName ?? "Window",
                systemImage: "app.window",
                icon: application.flatMap { applicationIcons[$0.processID] },
                pickerPlacement: isUtility ? .utility : ScreenSourcePickerOrganization.placement(
                    ScreenSourcePickerPlacementRequest(
                        binding: binding,
                        recentBundleIdentifiers: recentBundleIdentifiers
                    )
                )
            )
        }
        .sorted { lhs, rhs in
            let lhsLabel = "\(lhs.subtitle) \(lhs.title)"
            let rhsLabel = "\(rhs.subtitle) \(rhs.title)"
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }

        return displayOptions + sortedApplicationOptions + windowOptions
    }

    static func preferredWindowBinding(
        context: WindowSourceSelectionContext
    ) -> ScreenSourceBinding? {
        let windowBindings = context.availableSources
            .map(\.binding)
            .filter { $0.kind == .window }
        guard !windowBindings.isEmpty else { return nil }

        if let targetWindow = context.targetWindow {
            let processMatches = windowBindings.filter { binding in
                guard let processID = targetWindow.processID else {
                    return binding.applicationName == targetWindow.appName
                }
                return binding.processID == processID
            }
            if let windowTitle = targetWindow.windowTitle,
               let titleMatch = processMatches.first(where: { $0.windowTitle == windowTitle }) {
                return titleMatch
            }
            if let processMatch = processMatches.first {
                return processMatch
            }
        }

        guard context.currentSource.kind == .application else { return nil }
        let matching = windowBindings.filter {
            $0.matches(applicationBinding: context.currentSource)
        }
        if let displayID = context.currentSource.displayID,
           let sameDisplay = matching.first(where: { $0.displayID == displayID }) {
            return sameDisplay
        }
        return matching.first
    }

    static func canUseAppOnlyCapture(
        current: ScreenSourceBinding?,
        lastApplication: ScreenSourceBinding?,
        available: [ScreenSourceOption]
    ) -> Bool {
        current?.kind == .application
            || lastApplication != nil
            || available.contains { $0.binding.kind == .application }
    }

    static func readableApplicationName(_ name: String?) -> String? {
        collapsedDisplayName(name, generic: ["Application", "Window"])
    }

    static func readableWindowTitle(_ title: String?) -> String? {
        collapsedDisplayName(title, generic: ["Untitled", "Untitled window", "Window", "New Window"])
    }

    static func applicationKey(
        bundleIdentifier: String?,
        processID: pid_t?,
        applicationName: String?
    ) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        if let processID {
            return "pid:\(processID)"
        }
        return "name:\(readableApplicationName(applicationName) ?? "unknown")"
    }

    static func isIgnoredApplication(
        bundleIdentifier: String?,
        applicationName: String?
    ) -> Bool {
        if let bundleIdentifier, ignoredBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        guard let applicationName = readableApplicationName(applicationName) else {
            return true
        }
        let ignoredExactNames: Set<String> = [
            "Accessibility",
            "AirDrop",
            "Control Center",
            "Dock",
            "Notification Center",
            "SystemUIServer",
            "TextInputMenuAgent",
            "WindowManager"
        ]
        if ignoredExactNames.contains(applicationName) {
            return true
        }

        let ignoredNameFragments = [
            "AutoFill",
            "Display Backstop",
            "Helper",
            "LifecycleKeepalive",
            "StatusIndicator",
            "underbelly"
        ]
        return ignoredNameFragments.contains { applicationName.localizedCaseInsensitiveContains($0) }
    }

    static func isIgnoredWindow(
        bundleIdentifier: String?,
        applicationName: String?,
        title: String?
    ) -> Bool {
        if let bundleIdentifier, ignoredBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if isIgnoredApplication(bundleIdentifier: bundleIdentifier, applicationName: applicationName) {
            return true
        }

        let ignoredApplicationNames: Set<String> = [
            "Accessibility",
            "Control Center",
            "Dock",
            "Notification Center",
            "StatusIndicator",
            "SystemUIServer",
            "TextInputMenuAgent",
            "WindowManager",
            "underbelly"
        ]
        if let applicationName,
           ignoredApplicationNames.contains(applicationName) {
            return true
        }

        let ignoredTitleFragments = [
            "Software Cursor",
            "Display Backstop",
            "Item-0",
            "LifecycleKeepalive",
            "StatusItem",
            "StatusIndicator",
            "Menubar",
            "Menu Bar",
            "underbelly"
        ]
        let title = title ?? ""
        return ignoredTitleFragments.contains { title.localizedCaseInsensitiveContains($0) }
    }

    private static let ignoredBundleIdentifiers: Set<String> = [
        "com.apple.AirDropUIAgent",
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.ScreenContinuity",
        "com.apple.Siri",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
        "com.apple.TextInputMenuAgent",
        "com.apple.WindowManager",
        "com.apple.wallpaper"
    ]

    private static func collapsedDisplayName(_ name: String?, generic: [String]) -> String? {
        guard let name else { return nil }
        let collapsed = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        guard !generic.contains(where: { collapsed.localizedCaseInsensitiveCompare($0) == .orderedSame }) else {
            return nil
        }
        return collapsed
    }

    private static func appIcon(bundleIdentifier: String?, processID: pid_t?) -> NSImage? {
        if let processID,
           let icon = NSRunningApplication(processIdentifier: processID)?.icon {
            return icon
        }
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}
