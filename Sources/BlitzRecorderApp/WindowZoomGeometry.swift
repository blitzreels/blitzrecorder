import CoreGraphics

enum WindowZoomGeometry {
    static let minimumZoom: CGFloat = 0.5
    static let maximumZoom: CGFloat = 1.5

    static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, zoom))
    }

    static func sourceFrame(for slotFrame: CGRect, zoom: CGFloat) -> CGRect {
        let zoom = clampedZoom(zoom)
        let width = slotFrame.width / zoom
        let height = slotFrame.height / zoom
        return CGRect(
            x: slotFrame.midX - width / 2,
            y: slotFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
