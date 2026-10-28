import AppKit

extension PreviewStageView {
    func layoutPassKey() -> LayoutPassKey {
        LayoutPassKey(
            bounds: bounds,
            captureLayout: captureLayout,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled,
            isScreenCropEditingEnabled: isScreenCropEditingEnabled,
            enabledSources: enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource,
            cameraSourceAspectRatio: cameraPreview.currentSourceAspectRatio,
            sceneLayout: sceneLayout,
            screenFillsSceneFrame: screenFillsSceneFrame,
            screenCrop: screenCrop,
            screenSourceAspectRatio: effectiveScreenSourceAspectRatio,
            cameraCropAmount: cameraCropAmount,
            cameraCropPosition: cameraCropPosition,
            canvasBackgroundStyle: canvasBackgroundStyle,
            canvasPadding: canvasPadding,
            screenContentMode: screenContentMode,
            cameraContentMode: cameraContentMode,
            cameraFramePadding: cameraFramePadding,
            cameraShadowEnabled: cameraShadowEnabled,
            screenCornerRadius: screenCornerRadius,
            screenShadowEnabled: screenShadowEnabled,
            cameraCornerRadius: cameraCornerRadius
        )
    }

    func fittedCropEditingCanvas(in rect: NSRect) -> NSRect {
        let canvas = PreviewStageLayout.fittedCanvas(in: rect, captureLayout: captureLayout)
        guard isCameraCropEditingEnabled, enabledSources.contains(.camera) else { return canvas }
        return PreviewStageLayout.cropEditingCanvas(.init(
            fittedCanvas: canvas,
            rect: rect,
            cameraLayer: cameraCropLayer,
            cameraSourceAspectRatio: cameraPreview(for: cameraCropLayer).currentSourceAspectRatio,
            geometry: renderGeometry(in: canvas)
        ))
    }

    func skipsUnchangedLayoutPass(_ key: LayoutPassKey) -> Bool {
        guard lastLayoutPassKey == key else { return false }
        if canvasBackgroundAnimated {
            updateBackgroundAnimation()
        }
        return true
    }

    func relayoutCanvasImmediately() {
        if skipsUnchangedLayoutPass(layoutPassKey()) { return }
        needsLayout = true
        if !bounds.isEmpty {
            layout()
        }
        needsDisplay = true
        safeZoneOverlay.needsDisplay = true
        selectionOverlay.needsDisplay = true
        outlineOverlay.needsDisplay = true
        invalidateResizeCursorRects()
    }
}

enum LayoutPassKeyDiff {
    struct Request {
        let previous: PreviewStagePassKeys.LayoutPassKey
        let next: PreviewStagePassKeys.LayoutPassKey
    }

    static func changedFields(_ request: Request) -> String {
        let next = Dictionary(Mirror(reflecting: request.next).children.compactMap { child in
            child.label.map { ($0, String(describing: child.value)) }
        }, uniquingKeysWith: { lhs, _ in lhs })
        return Mirror(reflecting: request.previous).children.compactMap { child -> String? in
            guard let label = child.label, let value = next[label] else { return nil }
            let old = String(describing: child.value)
            return old == value ? nil : "\(label): \(old.prefix(80)) -> \(value.prefix(80))"
        }.joined(separator: " | ")
    }
}
