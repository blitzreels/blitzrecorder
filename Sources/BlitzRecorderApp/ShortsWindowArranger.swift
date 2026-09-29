import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
enum ShortsWindowArranger {
    static var fitRevision = 0

    static func cancelPendingFits() {
        fitRevision += 1
    }

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

    static func fitFrontWindow(
        displayID: String?,
        captureLayout: CaptureLayout,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        canvasPadding: CGFloat = 0,
        zoom: CGFloat
    ) async throws -> ShortsWindowArrangement {
        try requireAccessibilityTrust()

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
        let candidate = try frontmostCandidate(on: screen)
        let window = try accessibilityWindow(for: candidate)
        let appliedFrame = try await applyFittingPlan(.init(window: window, plan: plan, screen: screen))

        return arrangement(.init(
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: appliedFrame,
            screen: screen,
            fittingPlan: plan
        ))
    }

    static func screenItemForFrontWindow(displayID: String?) throws -> ShortsWindowArrangement {
        let screen = try targetScreen(displayID: displayID)
        let candidate = try frontmostCandidate(on: screen)
        let appKitFrame = TargetWindowFitting.clamped(
            frame: appKitFrame(for: candidate.bounds, on: screen),
            in: screen.visibleFrame
        )

        return arrangement(.init(
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: appKitFrame,
            screen: screen,
            fittingPlan: nil
        ))
    }

    static func resizeFrontWindow(
        displayID: String?,
        widthDelta: CGFloat,
        heightDelta: CGFloat
    ) throws -> ShortsWindowArrangement {
        try applyFrontWindowFrame(.init(displayID: displayID) { frame in
            resizing(frame, widthDelta: widthDelta, heightDelta: heightDelta)
        })
    }

    static func setFrontWindowSize(
        displayID: String?,
        width: CGFloat,
        height: CGFloat
    ) throws -> ShortsWindowArrangement {
        try applyFrontWindowFrame(.init(displayID: displayID) { frame in
            CGRect(
                x: frame.midX - width / 2,
                y: frame.midY - height / 2,
                width: max(320, width),
                height: max(220, height)
            )
        })
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
        let candidate = WindowCandidate(ownerPID: ownerPID, ownerName: appName, title: title, bounds: bounds)
        return try await fit(
            FitRequest(appName: appName, displayID: displayID, captureLayout: captureLayout, sceneLayout: sceneLayout,
                       enabledSources: enabledSources, canvasPadding: canvasPadding, zoom: zoom),
            window: { _ in try accessibilityWindow(for: candidate) },
            title: { _ in title }
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
        try await fit(
            FitRequest(appName: appName, displayID: displayID, captureLayout: captureLayout, sceneLayout: sceneLayout,
                       enabledSources: enabledSources, canvasPadding: canvasPadding, zoom: zoom),
            window: { screen in try primaryAccessibilityWindow(ownerPID: ownerPID, on: screen) },
            title: { window in self.title(of: window) }
        )
    }

    private struct FitRequest {
        let appName: String
        let displayID: String?
        let captureLayout: CaptureLayout
        let sceneLayout: SceneLayout
        let enabledSources: Set<CaptureSource>
        let canvasPadding: CGFloat
        let zoom: CGFloat
    }

    private static func fit(
        _ request: FitRequest,
        window resolveWindow: (NSScreen) throws -> AXUIElement,
        title resolveTitle: (AXUIElement) -> String?
    ) async throws -> ShortsWindowArrangement {
        try requireAccessibilityTrust()

        let screen = try targetScreen(displayID: request.displayID)
        let plan = TargetWindowFitting.plan(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            captureLayout: request.captureLayout,
            sceneLayout: request.sceneLayout,
            enabledSources: request.enabledSources,
            canvasPadding: request.canvasPadding,
            zoom: request.zoom
        )
        let window = try resolveWindow(screen)
        let appliedFrame = try await applyFittingPlan(.init(window: window, plan: plan, screen: screen))

        return arrangement(.init(
            appName: request.appName,
            windowTitle: resolveTitle(window),
            frame: appliedFrame,
            screen: screen,
            fittingPlan: plan
        ))
    }

    private struct ArrangementRequest {
        let appName: String
        let windowTitle: String?
        let frame: CGRect
        let screen: NSScreen
        let fittingPlan: TargetWindowFittingPlan?
    }

    private static func arrangement(_ request: ArrangementRequest) -> ShortsWindowArrangement {
        ShortsWindowArrangement(
            appName: request.appName,
            windowTitle: request.windowTitle,
            frame: request.frame,
            screenCrop: TargetWindowFitting.screenCrop(for: request.frame, in: request.screen.frame),
            fittedZoom: request.fittingPlan.map { $0.unscaledWindowFrame.width / max(1, request.frame.width) }
        )
    }

    private struct FrontWindowFrameRequest {
        let displayID: String?
        let targetFrame: (CGRect) -> CGRect
    }

    private static func applyFrontWindowFrame(_ request: FrontWindowFrameRequest) throws -> ShortsWindowArrangement {
        try requireAccessibilityTrust()

        let screen = try targetScreen(displayID: request.displayID)
        let candidate = try frontmostCandidate(on: screen)
        let window = try accessibilityWindow(for: candidate)
        guard let frame = frame(of: window) else {
            throw ShortsWindowArrangerError.noWindowFound
        }

        let targetFrame = TargetWindowFitting.clamped(
            frame: request.targetFrame(frame),
            in: accessibilityFrame(for: screen.visibleFrame, on: screen)
        )
        let appliedFrame = try set(window: window, frame: targetFrame)

        return arrangement(.init(
            appName: candidate.ownerName,
            windowTitle: candidate.title,
            frame: appKitFrame(for: appliedFrame, on: screen),
            screen: screen,
            fittingPlan: nil
        ))
    }
}
