import AppKit
import QuartzCore

func performWithoutUIAnimation(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        context.allowsImplicitAnimation = false
        updates()
    }
    CATransaction.commit()
}

let previewLayerNoResizeActions: [String: any CAAction] = [
    "frame": NSNull(),
    "bounds": NSNull(),
    "position": NSNull(),
    "contents": NSNull()
]
