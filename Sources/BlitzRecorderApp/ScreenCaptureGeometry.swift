import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureGeometry {
    static func screenSourceGeometry(for settings: RecordingSettings) -> ScreenSourceGeometry {
        ScreenSourceGeometry(settings: settings)
    }

    static func screenSourceGeometry(for settings: RecordingSettings, display: SCDisplay) -> ScreenSourceGeometry {
        ScreenSourceGeometry(
            usesPickedContent: false,
            selectedDisplayID: String(display.displayID),
            normalizedCrop: settings.screenCrop,
            sourceAspectRatio: screenSourceAspectRatio(
                for: settings,
                fallback: aspectRatio(width: display.width, height: display.height)
            )
        )
    }

    static func screenSourceGeometry(for settings: RecordingSettings, pickedFilter: SCContentFilter) -> ScreenSourceGeometry {
        ScreenSourceGeometry(
            usesPickedContent: true,
            selectedDisplayID: settings.selectedDisplayID,
            normalizedCrop: nil,
            sourceAspectRatio: pickedContentAspectRatio(for: pickedFilter)
        )
    }

    static func display(from displays: [SCDisplay], settings: RecordingSettings) -> SCDisplay? {
        if let selectedDisplayID = settings.selectedDisplayID,
           let numericID = UInt32(selectedDisplayID),
           let display = displays.first(where: { $0.displayID == numericID }) {
            return display
        }
        return displays.first(where: { CGMainDisplayID() == $0.displayID }) ?? displays.first
    }

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
        }
    }

    static func previewDimensions(for display: SCDisplay) -> (width: Int, height: Int) {
        dimensions(forAspectRatio: aspectRatio(width: display.width, height: display.height), longEdge: 1280)
    }

    static func previewDimensions(for display: SCDisplay, settings: RecordingSettings) -> (width: Int, height: Int) {
        dimensions(
            forAspectRatio: screenSourceGeometry(for: settings, display: display).aspectRatio(),
            longEdge: 1280
        )
    }

    static func previewDimensions(for pickedFilter: SCContentFilter) -> (width: Int, height: Int) {
        dimensions(forAspectRatio: pickedContentAspectRatio(for: pickedFilter), longEdge: 1280)
    }

    static func sourceRect(for display: SCDisplay, settings: RecordingSettings) -> CGRect {
        let fullRect = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        return screenSourceGeometry(for: settings, display: display).sourceRect(in: fullRect)
    }

    static func sourceRect(for display: SCDisplay, layout: CaptureLayout) -> CGRect {
        CGRect(x: 0, y: 0, width: display.width, height: display.height)
    }

    static func screenSourceAspectRatio(for settings: RecordingSettings, fallback: CGFloat) -> CGFloat {
        if let screenCrop = settings.screenCrop, screenCrop.width > 0, screenCrop.height > 0 {
            return screenCrop.width / screenCrop.height
        }
        return fallback
    }

    static func pickedContentAspectRatio(for filter: SCContentFilter) -> CGFloat {
        let rect = SCShareableContent.info(for: filter).contentRect
        guard rect.width > 0, rect.height > 0 else {
            return SceneLayout.defaultScreenAspectRatio
        }
        return rect.width / rect.height
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

    private static func aspectRatio(width: Int, height: Int) -> CGFloat {
        guard height > 0 else { return SceneLayout.defaultScreenAspectRatio }
        return CGFloat(width) / CGFloat(height)
    }

    private static func evenDimension(_ value: Int) -> Int {
        let value = max(2, value)
        return value.isMultiple(of: 2) ? value : value + 1
    }
}
