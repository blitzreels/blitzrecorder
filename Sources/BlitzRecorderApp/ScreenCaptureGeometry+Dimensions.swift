import CoreGraphics
import ScreenCaptureKit

extension ScreenCaptureGeometry {
    static func outputDimensions(for settings: RecordingSettings) -> (width: Int, height: Int) {
        settings.outputResolution.dimensions(for: settings.layout)
    }

    static func screenCaptureDimensions(for settings: RecordingSettings) -> (width: Int, height: Int) {
        screenCaptureDimensions(for: settings, sourceAspectRatio: settings.layout.aspectRatio)
    }

    static func screenCaptureDimensions(
        for settings: RecordingSettings,
        pickedFilter: SCContentFilter
    ) -> (width: Int, height: Int) {
        screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: pickedContentAspectRatio(for: pickedFilter)
        )
    }

    static func screenCaptureDimensions(
        for settings: RecordingSettings,
        display: SCDisplay
    ) -> (width: Int, height: Int) {
        screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: screenSourceAspectRatio(
                for: settings,
                fallback: aspectRatio(width: display.width, height: display.height)
            )
        )
    }

    static func screenCaptureDimensions(
        for settings: RecordingSettings,
        sourceAspectRatio: CGFloat
    ) -> (width: Int, height: Int) {
        let sourceAspectRatio = max(0.1, sourceAspectRatio)
        let shortEdge = CGFloat(settings.outputResolution.height)
        let dimensions: (width: Int, height: Int)
        if sourceAspectRatio >= 1 {
            dimensions = (
                width: evenDimension(Int((shortEdge * sourceAspectRatio).rounded())),
                height: evenDimension(Int(shortEdge.rounded()))
            )
        } else {
            dimensions = (
                width: evenDimension(Int(shortEdge.rounded())),
                height: evenDimension(Int((shortEdge / sourceAspectRatio).rounded()))
            )
        }
        return dimensions
    }

    static func previewDimensions(for layout: CaptureLayout) -> (width: Int, height: Int) {
        switch layout {
        case .vertical:
            return (720, 1280)
        case .horizontal:
            return (1280, 720)
        case .square:
            return (720, 720)
        }
    }

    static func previewDimensions(forSourceAspectRatio sourceAspectRatio: CGFloat) -> (width: Int, height: Int) {
        dimensions(forAspectRatio: sourceAspectRatio, longEdge: 1280)
    }

    private static func dimensions(forAspectRatio aspectRatio: CGFloat, longEdge: Int) -> (width: Int, height: Int) {
        let aspectRatio = max(0.1, aspectRatio)
        if aspectRatio >= 1 {
            return (
                width: evenDimension(longEdge),
                height: evenDimension(Int((CGFloat(longEdge) / aspectRatio).rounded()))
            )
        }

        return (
            width: evenDimension(Int((CGFloat(longEdge) * aspectRatio).rounded())),
            height: evenDimension(longEdge)
        )
    }

    static func aspectRatio(width: Int, height: Int) -> CGFloat {
        guard height > 0 else { return SceneLayout.defaultScreenAspectRatio }
        return CGFloat(width) / CGFloat(height)
    }

    private static func evenDimension(_ value: Int) -> Int {
        let value = max(2, value)
        return value.isMultiple(of: 2) ? value : value + 1
    }
}
