import CoreGraphics

enum ScreenSourceZoomGeometry {
    static let minimumZoom: CGFloat = 0.5
    static let maximumZoom: CGFloat = 2

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, zoom))
    }
}
