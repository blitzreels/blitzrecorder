import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

extension ShortsWindowArranger {
    private struct FittedWindowRequest {
        let window: AXUIElement
        let requested: CGRect
        let available: CGRect
    }

    struct FittingPlanApplication {
        let window: AXUIElement
        let plan: TargetWindowFittingPlan
        let screen: NSScreen
    }

    static func applyFittingPlan(_ request: FittingPlanApplication) async throws -> CGRect {
        let appliedAXFrame = try await setFittedWindow(.init(
            window: request.window,
            requested: accessibilityFrame(for: request.plan.windowFrame, on: request.screen),
            available: accessibilityFrame(for: request.screen.visibleFrame, on: request.screen)
        ))
        return appKitFrame(for: appliedAXFrame, on: request.screen)
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
                try await Task.sleep(for: WindowFrameWriter.settlingInterval)
                guard fitRevision == request.revision else { throw CancellationError() }
            },
            read: {
                guard let frame = frame(of: request.window) else { throw ShortsWindowArrangerError.noWindowFound }
                return frame
            }
        ))
    }

    static func set(window: AXUIElement, frame targetFrame: CGRect) throws -> CGRect {
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

    static func resizing(
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
}
