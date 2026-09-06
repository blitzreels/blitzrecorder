import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum ShortsWindowArrangerError: LocalizedError {
    case accessibilityPermissionRequired
    case displayUnavailable
    case noWindowFound
    case windowListUnavailable
    case windowMoveFailed
    case windowNotResizable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Allow BlitzRecorder in Accessibility, then try again."
        case .displayUnavailable:
            return "Selected display is not available."
        case .noWindowFound:
            return "No other window found to fit."
        case .windowListUnavailable:
            return "Could not read the visible window list."
        case .windowMoveFailed:
            return "Could not move the target window."
        case .windowNotResizable:
            return "This app does not allow window resizing. Use Adjust crop instead."
        }
    }
}

enum ScreenWindowFitRetry {
    static let maximumAttempts = 3

    static func run<Value>(_ operation: () async throws -> Value) async throws -> Value {
        for attempt in 1...maximumAttempts {
            do {
                return try await operation()
            } catch ShortsWindowArrangerError.windowMoveFailed where attempt < maximumAttempts {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        throw ShortsWindowArrangerError.windowMoveFailed
    }
}


@MainActor
enum WindowFrameWriter {
    enum Change {
        case size(CGSize)
        case position(CGPoint)
    }

    struct Request {
        let frame: CGRect
        let write: (Change) throws -> Void
        let settle: () async throws -> Void
        let read: () throws -> CGRect
    }

    static func apply(_ request: Request) async throws -> CGRect {
        try request.write(.size(request.frame.size))
        try await request.settle()
        try request.write(.position(request.frame.origin))
        try await request.settle()
        try request.write(.size(request.frame.size))
        try await request.settle()
        return try request.read()
    }
}

struct ShortsWindowArrangement {
    let appName: String
    let windowTitle: String?
    let frame: CGRect
    let screenCrop: CGRect
    var fittedZoom: CGFloat? = nil

    var message: String {
        let name = windowTitle?.isEmpty == false ? "\(appName) - \(windowTitle!)" : appName
        return "Fitted \(name) and aligned screen capture."
    }

    var resizedMessage: String {
        let name = windowTitle?.isEmpty == false ? "\(appName) - \(windowTitle!)" : appName
        return "Resized \(name) to \(Int(frame.width))x\(Int(frame.height))."
    }

    var screenItemMessage: String {
        let name = windowTitle?.isEmpty == false ? "\(appName) - \(windowTitle!)" : appName
        return "Screen item now shows \(name)."
    }
}

struct TargetWindowInfo: Equatable {
    let processID: pid_t?
    let appName: String
    let windowTitle: String?
    let frame: CGRect

    var title: String {
        appName
    }

    var detail: String {
        if let windowTitle, !windowTitle.isEmpty {
            return windowTitle
        }
        return "\(Int(frame.width))x\(Int(frame.height))"
    }

    init(processID: pid_t? = nil, appName: String, windowTitle: String?, frame: CGRect) {
        self.processID = processID
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
    }
}

@MainActor
enum ShortsWindowArranger {
    static func frontWindowInfo(displayID: String?) throws -> TargetWindowInfo {
        let screen = try targetScreen(displayID: displayID)
        let candidate = try frontmostCandidate(on: screen)
        return TargetWindowInfo(
            processID: candidate.ownerPID,
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: candidate.bounds
        )
    }

    static func fitFrontWindow(displayID: String?) async throws -> ShortsWindowArrangement {
        try await fitFrontWindow(displayID: displayID, zoom: 1)
    }

    static func fitFrontWindow(displayID: String?, zoom: CGFloat) async throws -> ShortsWindowArrangement {
        try await fitFrontWindow(
            displayID: displayID,
            captureLayout: .vertical,
            screenSlot: SceneSlotGeometry.shortsTopHalfSlot,
            zoom: zoom
        )
    }

    static func fitFrontWindow(
        displayID: String?,
        captureLayout: CaptureLayout,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        canvasPadding: CGFloat = 0,
        zoom: CGFloat
    ) async throws -> ShortsWindowArrangement {
        try await fitFrontWindow(
            displayID: displayID,
            fittingPlan: { screen in
                TargetWindowFitting.plan(
                    screenFrame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    captureLayout: captureLayout,
                    sceneLayout: sceneLayout,
                    enabledSources: enabledSources,
                    canvasPadding: canvasPadding,
                    zoom: zoom
                )
            }
        )
    }

    static func fitFrontWindow(
        displayID: String?,
        captureLayout: CaptureLayout,
        screenSlot: CGRect,
        canvasPadding: CGFloat = 0,
        zoom: CGFloat
    ) async throws -> ShortsWindowArrangement {
        try await fitFrontWindow(
            displayID: displayID,
            fittingPlan: { screen in
                TargetWindowFitting.plan(
                    screenFrame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    captureLayout: captureLayout,
                    screenSlot: screenSlot,
                    canvasPadding: canvasPadding,
                    zoom: zoom
                )
            }
        )
    }

    private static func fitFrontWindow(
        displayID: String?,
        fittingPlan: (NSScreen) -> TargetWindowFittingPlan
    ) async throws -> ShortsWindowArrangement {
        guard accessibilityTrusted(prompt: true) else {
            throw ShortsWindowArrangerError.accessibilityPermissionRequired
        }

        let screen = try targetScreen(displayID: displayID)
        let plan = fittingPlan(screen)
        let targetFrame = plan.windowFrame
        let targetAXFrame = accessibilityFrame(for: targetFrame, on: screen)
        let candidate = try frontmostCandidate(on: screen)
        let window = try accessibilityWindow(for: candidate)

        let appliedAXFrame = try await setFittedWindow(.init(
            window: window,
            requested: targetAXFrame,
            available: accessibilityFrame(for: screen.visibleFrame, on: screen)
        ))
        let appliedFrame = appKitFrame(for: appliedAXFrame, on: screen)

        return ShortsWindowArrangement(
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: appliedFrame,
            screenCrop: TargetWindowFitting.screenCrop(for: appliedFrame, in: screen.frame),
            fittedZoom: plan.unscaledWindowFrame.width / max(1, appliedFrame.width)
        )
    }

    static func screenItemForFrontWindow(displayID: String?) throws -> ShortsWindowArrangement {
        let screen = try targetScreen(displayID: displayID)
        let candidate = try frontmostCandidate(on: screen)
        let appKitFrame = TargetWindowFitting.clamped(
            frame: appKitFrame(for: candidate.bounds, on: screen),
            in: screen.visibleFrame
        )

        return ShortsWindowArrangement(
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: appKitFrame,
            screenCrop: TargetWindowFitting.screenCrop(for: appKitFrame, in: screen.frame)
        )
    }

    static func resizeFrontWindow(
        displayID: String?,
        widthDelta: CGFloat,
        heightDelta: CGFloat
    ) throws -> ShortsWindowArrangement {
        guard accessibilityTrusted(prompt: true) else {
            throw ShortsWindowArrangerError.accessibilityPermissionRequired
        }

        let screen = try targetScreen(displayID: displayID)
        let candidate = try frontmostCandidate(on: screen)
        let window = try accessibilityWindow(for: candidate)
        guard let frame = frame(of: window) else {
            throw ShortsWindowArrangerError.noWindowFound
        }

        let targetFrame = TargetWindowFitting.clamped(
            frame: resizing(frame, widthDelta: widthDelta, heightDelta: heightDelta),
            in: accessibilityFrame(for: screen.visibleFrame, on: screen)
        )
        let appliedFrame = try set(window: window, frame: targetFrame)

        let appKitFrame = appKitFrame(for: appliedFrame, on: screen)
        return ShortsWindowArrangement(
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: appKitFrame,
            screenCrop: TargetWindowFitting.screenCrop(for: appKitFrame, in: screen.frame)
        )
    }

    static func setFrontWindowSize(
        displayID: String?,
        width: CGFloat,
        height: CGFloat
    ) throws -> ShortsWindowArrangement {
        guard accessibilityTrusted(prompt: true) else {
            throw ShortsWindowArrangerError.accessibilityPermissionRequired
        }

        let screen = try targetScreen(displayID: displayID)
        let candidate = try frontmostCandidate(on: screen)
        let window = try accessibilityWindow(for: candidate)
        guard let frame = frame(of: window) else {
            throw ShortsWindowArrangerError.noWindowFound
        }

        let targetFrame = TargetWindowFitting.clamped(
            frame: CGRect(
                x: frame.midX - width / 2,
                y: frame.midY - height / 2,
                width: max(320, width),
                height: max(220, height)
            ),
            in: accessibilityFrame(for: screen.visibleFrame, on: screen)
        )
        let appliedFrame = try set(window: window, frame: targetFrame)

        let appKitFrame = appKitFrame(for: appliedFrame, on: screen)
        return ShortsWindowArrangement(
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: appKitFrame,
            screenCrop: TargetWindowFitting.screenCrop(for: appKitFrame, in: screen.frame)
        )
    }

    @discardableResult
    static func fitWindow(
        ownerPID: pid_t,
        bounds: CGRect,
        title: String?,
        appName: String,
        displayID: String?,
        captureLayout: CaptureLayout,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        canvasPadding: CGFloat = 0,
        zoom: CGFloat = 1
    ) async throws -> ShortsWindowArrangement {
        guard accessibilityTrusted(prompt: false) else {
            throw ShortsWindowArrangerError.accessibilityPermissionRequired
        }

        let screen = try targetScreen(displayID: displayID)
        let plan = TargetWindowFitting.plan(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            captureLayout: captureLayout,
            sceneLayout: sceneLayout,
            enabledSources: enabledSources,
            canvasPadding: canvasPadding,
            zoom: zoom
        )
        let candidate = WindowCandidate(ownerPID: ownerPID, ownerName: appName, title: title, bounds: bounds)
        let window = try accessibilityWindow(for: candidate)
        let appliedAXFrame = try await setFittedWindow(.init(
            window: window,
            requested: accessibilityFrame(for: plan.windowFrame, on: screen),
            available: accessibilityFrame(for: screen.visibleFrame, on: screen)
        ))
        let appliedFrame = appKitFrame(for: appliedAXFrame, on: screen)

        return ShortsWindowArrangement(
            appName: appName,
            windowTitle: title,
            frame: appliedFrame,
            screenCrop: TargetWindowFitting.screenCrop(for: appliedFrame, in: screen.frame),
            fittedZoom: plan.unscaledWindowFrame.width / max(1, appliedFrame.width)
        )
    }

    @discardableResult
    static func fitAppWindow(
        ownerPID: pid_t,
        appName: String,
        displayID: String?,
        captureLayout: CaptureLayout,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        canvasPadding: CGFloat = 0,
        zoom: CGFloat = 1
    ) async throws -> ShortsWindowArrangement {
        guard accessibilityTrusted(prompt: false) else {
            throw ShortsWindowArrangerError.accessibilityPermissionRequired
        }

        let screen = try targetScreen(displayID: displayID)
        let plan = TargetWindowFitting.plan(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            captureLayout: captureLayout,
            sceneLayout: sceneLayout,
            enabledSources: enabledSources,
            canvasPadding: canvasPadding,
            zoom: zoom
        )
        let window = try primaryAccessibilityWindow(ownerPID: ownerPID, on: screen)
        let appliedAXFrame = try await setFittedWindow(.init(
            window: window,
            requested: accessibilityFrame(for: plan.windowFrame, on: screen),
            available: accessibilityFrame(for: screen.visibleFrame, on: screen)
        ))
        let appliedFrame = appKitFrame(for: appliedAXFrame, on: screen)

        return ShortsWindowArrangement(
            appName: appName,
            windowTitle: title(of: window),
            frame: appliedFrame,
            screenCrop: TargetWindowFitting.screenCrop(for: appliedFrame, in: screen.frame),
            fittedZoom: plan.unscaledWindowFrame.width / max(1, appliedFrame.width)
        )
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static func targetScreen(displayID: String?) throws -> NSScreen {
        let selectedID = displayID.flatMap(UInt32.init) ?? CGMainDisplayID()
        if let screen = NSScreen.screens.first(where: { $0.displayID == selectedID }) {
            return screen
        }
        if let main = NSScreen.main {
            return main
        }
        throw ShortsWindowArrangerError.displayUnavailable
    }

    private static func accessibilityFrame(for appKitFrame: CGRect, on screen: NSScreen) -> CGRect {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
        return CGRect(
            x: appKitFrame.minX,
            y: desktopTop - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    private static func appKitFrame(for accessibilityFrame: CGRect, on screen: NSScreen) -> CGRect {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
        return CGRect(
            x: accessibilityFrame.minX,
            y: desktopTop - accessibilityFrame.maxY,
            width: accessibilityFrame.width,
            height: accessibilityFrame.height
        )
    }

    private static func frontmostCandidate(on screen: NSScreen) throws -> WindowCandidate {
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

    private static func accessibilityWindow(for candidate: WindowCandidate) throws -> AXUIElement {
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

    private static func primaryAccessibilityWindow(ownerPID: pid_t, on screen: NSScreen) throws -> AXUIElement {
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

    private struct FittedWindowRequest {
        let window: AXUIElement
        let requested: CGRect
        let available: CGRect
    }

    private static var fitRevision = 0

    static func cancelPendingFits() {
        fitRevision += 1
    }

    private static func setFittedWindow(_ request: FittedWindowRequest) async throws -> CGRect {
        fitRevision += 1
        let revision = fitRevision
        let applied = try await applyWindowFrame(.init(window: request.window, frame: request.requested, revision: revision))
        let constrained = TargetWindowFitting.fittedFrame(.init(
            requested: request.requested,
            minimumSize: CGSize(
                width: applied.width > request.requested.width + 2 ? applied.width : 0,
                height: applied.height > request.requested.height + 2 ? applied.height : 0
            ),
            available: request.available
        ))
        guard abs(constrained.width - applied.width) > 2
            || abs(constrained.height - applied.height) > 2
            || abs(constrained.minX - applied.minX) > 2
            || abs(constrained.minY - applied.minY) > 2 else { return applied }
        return try await applyWindowFrame(.init(window: request.window, frame: constrained, revision: revision))
    }

    private struct WindowFrameRequest {
        let window: AXUIElement
        let frame: CGRect
        let revision: Int
    }

    private static func applyWindowFrame(_ request: WindowFrameRequest) async throws -> CGRect {
        var sizeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(request.window, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              sizeSettable.boolValue else { throw ShortsWindowArrangerError.windowNotResizable }
        return try await WindowFrameWriter.apply(.init(
            frame: request.frame,
            write: { change in
                guard fitRevision == request.revision else { throw CancellationError() }
                let attribute: CFString
                let value: AXValue?
                switch change {
                case .size(var size):
                    attribute = kAXSizeAttribute as CFString
                    value = AXValueCreate(.cgSize, &size)
                case .position(var position):
                    attribute = kAXPositionAttribute as CFString
                    value = AXValueCreate(.cgPoint, &position)
                }
                guard let value,
                      AXUIElementSetAttributeValue(request.window, attribute, value) == .success else {
                    throw ShortsWindowArrangerError.windowMoveFailed
                }
            },
            settle: {
                try await Task.sleep(for: .milliseconds(120))
                guard fitRevision == request.revision else { throw CancellationError() }
            },
            read: {
                guard let frame = frame(of: request.window) else { throw ShortsWindowArrangerError.noWindowFound }
                return frame
            }
        ))
    }

    private static func set(window: AXUIElement, frame targetFrame: CGRect) throws -> CGRect {
        var position = CGPoint(x: targetFrame.minX, y: targetFrame.minY)
        var size = CGSize(width: targetFrame.width, height: targetFrame.height)

        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw ShortsWindowArrangerError.windowMoveFailed
        }

        var sizeSettable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            window,
            kAXSizeAttribute as CFString,
            &sizeSettable
        )
        guard settableError == .success, sizeSettable.boolValue else {
            throw ShortsWindowArrangerError.windowNotResizable
        }

        let sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        guard positionError == .success, sizeError == .success else {
            throw ShortsWindowArrangerError.windowMoveFailed
        }

        return frame(of: window) ?? targetFrame
    }

    private static func resizing(
        _ frame: CGRect,
        widthDelta: CGFloat,
        heightDelta: CGFloat
    ) -> CGRect {
        let minWidth: CGFloat = 320
        let minHeight: CGFloat = 220
        let width = max(minWidth, frame.width + widthDelta)
        let height = max(minHeight, frame.height + heightDelta)
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: window),
              let sizeValue = copyAttribute(kAXSizeAttribute, from: window) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func title(of window: AXUIElement) -> String? {
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
}

private struct WindowCandidate {
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

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }
}

struct AppWindowSelectionCandidate: Equatable {
    let id: Int
    let frame: CGRect
    let isStandard: Bool

    var area: CGFloat {
        frame.width * frame.height
    }

    var isUsablePrimary: Bool {
        frame.width >= 320 && frame.height >= 220 && area > 0
    }
}

enum AppWindowSelection {
    static func primary(
        from candidates: [AppWindowSelectionCandidate],
        focusedID: Int?,
        mainID: Int?
    ) -> AppWindowSelectionCandidate? {
        let validCandidates = candidates.filter { $0.area > 0 }
        let standardCandidates = validCandidates.filter(\.isStandard)
        let pool = standardCandidates.isEmpty ? validCandidates : standardCandidates

        if let focused = candidate(with: focusedID, in: pool), focused.isUsablePrimary {
            return focused
        }
        if let main = candidate(with: mainID, in: pool), main.isUsablePrimary {
            return main
        }
        return pool.max(by: { $0.area < $1.area })
    }

    private static func candidate(
        with id: Int?,
        in candidates: [AppWindowSelectionCandidate]
    ) -> AppWindowSelectionCandidate? {
        guard let id else { return nil }
        return candidates.first { $0.id == id }
    }
}
