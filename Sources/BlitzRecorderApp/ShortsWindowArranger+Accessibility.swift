import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

extension ShortsWindowArranger {
    static func requireAccessibilityTrust() throws {
        guard accessibilityTrusted(prompt: false) else {
            throw ShortsWindowArrangerError.accessibilityPermissionRequired
        }
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func targetScreen(displayID: String?) throws -> NSScreen {
        let selectedID = displayID.flatMap(UInt32.init) ?? CGMainDisplayID()
        if let screen = NSScreen.screens.first(where: { $0.displayID == selectedID }) {
            return screen
        }
        if let main = NSScreen.main {
            return main
        }
        throw ShortsWindowArrangerError.displayUnavailable
    }

    static func accessibilityFrame(for appKitFrame: CGRect, on screen: NSScreen) -> CGRect {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
        return CGRect(
            x: appKitFrame.minX,
            y: desktopTop - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    static func appKitFrame(for accessibilityFrame: CGRect, on screen: NSScreen) -> CGRect {
        self.accessibilityFrame(for: accessibilityFrame, on: screen)
    }

    static func frontmostCandidate(on screen: NSScreen) throws -> WindowCandidate {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw ShortsWindowArrangerError.windowListUnavailable
        }

        let ownPID = NSRunningApplication.current.processIdentifier
        let screenAXFrame = accessibilityFrame(for: screen.visibleFrame, on: screen)

        for info in rawWindows {
            guard let candidate = WindowCandidate(info: info),
                  candidate.ownerPID != ownPID,
                  candidate.layer == 0,
                  candidate.alpha > 0,
                  candidate.bounds.width >= 240,
                  candidate.bounds.height >= 160,
                  candidate.bounds.intersects(screenAXFrame) else {
                continue
            }
            return candidate
        }

        throw ShortsWindowArrangerError.noWindowFound
    }

    static func accessibilityWindow(for candidate: WindowCandidate) throws -> AXUIElement {
        let app = AXUIElementCreateApplication(candidate.ownerPID)
        guard let windowsValue = copyAttribute(kAXWindowsAttribute, from: app),
              let windows = windowsValue as? [AXUIElement] else {
            throw ShortsWindowArrangerError.noWindowFound
        }
        let movable = windows.filter { isMovableWindow($0) }
        if let matched = movable.first(where: { window($0, matches: candidate) }) {
            return matched
        }
        let titleMatches = movable.filter { title(of: $0) == candidate.title && candidate.title?.isEmpty == false }
        if titleMatches.count == 1, let match = titleMatches.first {
            return match
        }
        throw ShortsWindowArrangerError.noWindowFound
    }

    static func primaryAccessibilityWindow(ownerPID: pid_t, on screen: NSScreen) throws -> AXUIElement {
        let app = AXUIElementCreateApplication(ownerPID)

        guard let windowsValue = copyAttribute(kAXWindowsAttribute, from: app) else {
            throw ShortsWindowArrangerError.noWindowFound
        }
        let windows = windowsValue as? [AXUIElement] ?? []

        let movableWindows = windows.filter { isMovableWindow($0) }
        let screenAXFrame = accessibilityFrame(for: screen.visibleFrame, on: screen)
        let visibleOnTargetScreen = movableWindows.filter {
            frame(of: $0)?.intersects(screenAXFrame) == true
        }
        let displayScopedWindows = visibleOnTargetScreen.isEmpty ? movableWindows : visibleOnTargetScreen
        let standardWindows = displayScopedWindows.filter { isStandardWindow($0) }
        let windowsInPriorityPool = standardWindows.isEmpty ? displayScopedWindows : standardWindows
        let candidates = windowsInPriorityPool.enumerated().compactMap { index, window -> AppWindowSelectionCandidate? in
            guard let frame = frame(of: window) else { return nil }
            return AppWindowSelectionCandidate(
                id: index,
                frame: frame,
                isStandard: isStandardWindow(window)
            )
        }
        let focusedID = copyAttribute(kAXFocusedWindowAttribute, from: app)
            .flatMap { focused in
                windowsInPriorityPool.firstIndex(where: { CFEqual($0, focused) })
            }
        let mainID = copyAttribute(kAXMainWindowAttribute, from: app)
            .flatMap { main in
                windowsInPriorityPool.firstIndex(where: { CFEqual($0, main) })
            }
        guard let selected = AppWindowSelection.primary(
            from: candidates,
            focusedID: focusedID,
            mainID: mainID
        ) else {
            throw ShortsWindowArrangerError.noWindowFound
        }

        return windowsInPriorityPool[selected.id]
    }

    private static func window(_ window: AXUIElement, matches candidate: WindowCandidate) -> Bool {
        guard isMovableWindow(window),
              let frame = frame(of: window) else {
            return false
        }

        return abs(frame.minX - candidate.bounds.minX) < 4
            && abs(frame.minY - candidate.bounds.minY) < 4
            && abs(frame.width - candidate.bounds.width) < 8
            && abs(frame.height - candidate.bounds.height) < 8
    }

    private static func isMovableWindow(_ window: AXUIElement) -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute, from: window) else {
            return false
        }
        return role == kAXWindowRole as String
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        stringAttribute(kAXSubroleAttribute, from: window) == kAXStandardWindowSubrole as String
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: window),
              let sizeValue = copyAttribute(kAXSizeAttribute, from: window),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetType(sizeAXValue) == .cgSize else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    static func title(of window: AXUIElement) -> String? {
        stringAttribute(kAXTitleAttribute, from: window)
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        copyAttribute(attribute, from: element) as? String
    }

    private static func copyAttribute(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    struct WindowCandidate {
        let ownerPID: pid_t
        let ownerName: String
        let title: String?
        let bounds: CGRect
        let layer: Int
        let alpha: Double

        init(ownerPID: pid_t, ownerName: String, title: String?, bounds: CGRect) {
            self.ownerPID = ownerPID
            self.ownerName = ownerName
            self.title = title
            self.bounds = bounds
            self.layer = 0
            self.alpha = 1
        }

        init?(info: [String: Any]) {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }

            self.ownerPID = ownerPID
            self.ownerName = ownerName
            self.title = info[kCGWindowName as String] as? String
            self.bounds = bounds
            self.layer = layer
            self.alpha = info[kCGWindowAlpha as String] as? Double ?? 1
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
