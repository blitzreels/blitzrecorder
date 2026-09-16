import CoreGraphics

enum EditorSessionMetrics {
    static func timelineDuration(playbackDuration: Double, lastEventTime: Double) -> Double {
        if playbackDuration > 0 {
            return playbackDuration
        }
        return lastEventTime > 0 ? lastEventTime + 1 : 0
    }

    static func canvasAspectRatio(renderSize: CGSize, layout: CaptureLayout?) -> CGFloat {
        if renderSize.width > 0, renderSize.height > 0 {
            return renderSize.width / renderSize.height
        }
        return layout?.aspectRatio ?? 16.0 / 9.0
    }

    static func ratioLabel(_ layout: CaptureLayout?) -> String {
        layout?.shortLabel ?? "—"
    }
}
