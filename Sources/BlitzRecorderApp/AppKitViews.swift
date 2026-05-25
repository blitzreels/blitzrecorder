import AppKit
import AVFoundation
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

private let noResizeActions: [String: any CAAction] = [
    "frame": NSNull(),
    "bounds": NSNull(),
    "position": NSNull(),
    "contents": NSNull()
]

@MainActor
final class PreviewStageView: NSView {
    let screenPreview = ScreenPreviewView()
    let cameraPreview = CameraPreviewView()
    private let canvasBackgroundLayer = CAGradientLayer()
    private let safeZoneOverlay = SafeZoneOverlayView()
    private let selectionOverlay = SceneSelectionOverlayView()
    private let outlineOverlay = SourceOutlineView()
    private let screenCanvasMask = CAShapeLayer()
    private let cameraCanvasMask = CAShapeLayer()
    private var canvasFrame = NSRect.zero
    private var dragMode: DragMode?
    private var trackingArea: NSTrackingArea?
    private var cameraCropDraftAmount: CGPoint?
    private var cameraCropDraftPosition: CGPoint?
    private let resizeHandleOutset: CGFloat = 14
    private let minimumCropScale: CGFloat = 0.25
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var selectedLayer: SceneLayerKind = .camera {
        didSet {
            updateSelectionOverlay()
            invalidateResizeCursorRects()
        }
    }
    var onLayerFrameChanged: ((SceneLayerKind, CGRect) -> Void)?
    var onSceneLayoutChanged: ((SceneLayout) -> Void)?
    var onLayerSelected: ((SceneLayerKind) -> Void)?
    var onCameraCropChanged: ((CGPoint, CGPoint) -> Void)?
    var renderedCanvasAspectRatio: CGFloat {
        guard canvasFrame.height > 0 else { return 0 }
        return canvasFrame.width / canvasFrame.height
    }
    var renderedCanvasFrameForTesting: CGRect { canvasFrame }
    var renderedSelectionFrameForTesting: CGRect? { selectionOverlay.selectionFrame }

    var isCameraCropEditingEnabled: Bool = false {
        didSet {
            syncPreviewCrop()
            updateSelectionOverlay()
            invalidateResizeCursorRects()
        }
    }

    var captureLayout: CaptureLayout = .vertical {
        didSet {
            guard oldValue != captureLayout else { return }
            safeZoneOverlay.captureLayout = captureLayout
            updateSafeZoneOverlayVisibility()
            relayoutCanvasImmediately()
        }
    }

    var screenSourceAspectRatio: CGFloat = SceneLayout.defaultScreenAspectRatio {
        didSet {
            if oldValue != screenSourceAspectRatio {
                needsLayout = true
                needsDisplay = true
            }
        }
    }

    var cameraCropAmount: CGPoint = .zero {
        didSet {
            if !isCameraCropEditingEnabled {
                cameraPreview.sourceCropAmount = cameraCropAmount
            }
            updateSelectionOverlay()
        }
    }

    var cameraCropPosition: CGPoint = .zero {
        didSet {
            if !isCameraCropEditingEnabled {
                cameraPreview.sourceCropPosition = cameraCropPosition
            }
            updateSelectionOverlay()
        }
    }

    var canvasBackgroundStyle: CanvasBackgroundStyle = .black {
        didSet {
            applyCanvasBackgroundStyle()
        }
    }

    var canvasPadding: CGFloat = 0 {
        didSet {
            if !canvasFrame.isEmpty {
                applySceneFrames()
            }
            invalidateResizeCursorRects()
        }
    }

    var showsRuleOfThirdsOverlay: Bool = false {
        didSet {
            safeZoneOverlay.showsRuleOfThirdsOverlay = showsRuleOfThirdsOverlay
            updateSafeZoneOverlayVisibility()
            safeZoneOverlay.needsDisplay = true
        }
    }

    var socialSafeZoneOverlay: SocialVideoSafeZone = .none {
        didSet {
            safeZoneOverlay.socialSafeZoneOverlay = socialSafeZoneOverlay
            updateSafeZoneOverlayVisibility()
            safeZoneOverlay.needsDisplay = true
        }
    }

    var enabledSources: Set<CaptureSource> = [] {
        didSet {
            if !enabledSources.contains(selectedLayer.source),
               let firstLayer = SceneLayoutProjection.topLayer(in: sceneLayout, enabledSources: enabledSources) {
                selectedLayer = firstLayer
            }
            needsLayout = true
            invalidateResizeCursorRects()
        }
    }

    var sceneLayout = SceneLayout() {
        didSet {
            if !canvasFrame.isEmpty {
                applySceneFrames()
            }
            needsLayout = true
            needsDisplay = true
            invalidateResizeCursorRects()
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = false

        applyCanvasBackgroundStyle()
        canvasBackgroundLayer.zPosition = -1
        canvasBackgroundLayer.actions = [
            "frame": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "colors": NSNull(),
            "locations": NSNull()
        ]
        layer?.addSublayer(canvasBackgroundLayer)

        screenPreview.translatesAutoresizingMaskIntoConstraints = true
        cameraPreview.translatesAutoresizingMaskIntoConstraints = true
        safeZoneOverlay.translatesAutoresizingMaskIntoConstraints = true
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = true
        outlineOverlay.translatesAutoresizingMaskIntoConstraints = true
        safeZoneOverlay.wantsLayer = true
        safeZoneOverlay.showsRuleOfThirdsOverlay = showsRuleOfThirdsOverlay
        safeZoneOverlay.captureLayout = captureLayout
        safeZoneOverlay.socialSafeZoneOverlay = socialSafeZoneOverlay
        selectionOverlay.wantsLayer = true
        addSubview(screenPreview)
        addSubview(cameraPreview)
        addSubview(outlineOverlay)
        addSubview(safeZoneOverlay)
        addSubview(selectionOverlay)

        let noActions: [String: any CAAction] = [
            "path": NSNull(),
            "frame": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull()
        ]
        screenCanvasMask.actions = noActions
        screenCanvasMask.fillColor = NSColor.white.cgColor
        cameraCanvasMask.actions = noActions
        cameraCanvasMask.fillColor = NSColor.white.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()

        performWithoutUIAnimation {
            canvasFrame = fittedCanvas(in: bounds.insetBy(dx: resizeHandleOutset, dy: resizeHandleOutset))
            canvasBackgroundLayer.frame = canvasFrame
            applyLayerOrder()
            applySceneFrames()
            updateSelectionOverlay()
        }
        invalidateResizeCursorRects()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !canvasFrame.isEmpty else { return }

        if isCameraCropEditingEnabled, enabledSources.contains(.camera) {
            let frame = frame(for: .camera)
            let moveRect = frame.insetBy(dx: 12, dy: 12)
            if moveRect.width > 0, moveRect.height > 0 {
                addCursorRect(moveRect, cursor: .openHand)
            }
            for (anchor, rect) in resizeTargets(for: frame) {
                addCursorRect(rect, cursor: anchor.cursor)
            }
            return
        }

        for layer in SceneLayoutProjection.frontToBackOrder(for: sceneLayout) where enabledSources.contains(layer.source) {
            let frame = interactiveFrame(for: layer)
            let moveRect = frame.insetBy(dx: 12, dy: 12)
            if moveRect.width > 0, moveRect.height > 0 {
                addCursorRect(moveRect, cursor: .openHand)
            }
            guard layer == selectedLayer else { continue }
            for (anchor, rect) in resizeTargets(for: frame) {
                addCursorRect(rect, cursor: anchor.cursor)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    private func fittedCanvas(in rect: NSRect) -> NSRect {
        let aspect = captureLayout.aspectRatio
        let rectAspect = rect.width / rect.height
        if rectAspect > aspect {
            let width = floor(rect.height * aspect)
            return NSRect(
                x: rect.midX - width / 2,
                y: rect.minY,
                width: width,
                height: rect.height
            )
        }

        let height = floor(rect.width / aspect)
        return NSRect(
            x: rect.minX,
            y: rect.midY - height / 2,
            width: rect.width,
            height: height
        )
    }

    private func relayoutCanvasImmediately() {
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

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        if isCameraCropEditingEnabled,
           enabledSources.contains(.camera),
           let mode = cameraCropDragMode(at: location) {
            selectedLayer = .camera
            onLayerSelected?(.camera)
            dragMode = DragMode(
                kind: mode,
                layer: .camera,
                startPoint: location,
                startFrame: normalizedFrame(for: .camera),
                startCropAmount: activeCameraCropAmount,
                startCropPosition: activeCameraCropPosition
            )
            cursor(for: mode).set()
            needsDisplay = true
            return
        }

        if let (layer, anchor) = resizeHit(at: location) {
            selectedLayer = layer
            onLayerSelected?(layer)
            dragMode = DragMode(
                kind: .resize(anchor),
                layer: layer,
                startPoint: location,
                startFrame: normalizedInteractiveFrame(for: layer),
                startCropAmount: cameraCropAmount,
                startCropPosition: cameraCropPosition
            )
            anchor.cursor.set()
            needsDisplay = true
            return
        }

        guard canvasFrame.contains(location) else { return }

        guard let layer = layer(at: location) else { return }
        let wasSelected = layer == selectedLayer
        selectedLayer = layer
        onLayerSelected?(layer)
        let frame = interactiveFrame(for: layer)
        let mode: DragMode.Kind
        if wasSelected, let anchor = resizeAnchor(at: location, in: frame) {
            mode = .resize(anchor)
            anchor.cursor.set()
        } else {
            mode = .move
            NSCursor.closedHand.set()
        }
        dragMode = DragMode(
            kind: mode,
            layer: layer,
            startPoint: location,
            startFrame: mode.isResize ? normalizedInteractiveFrame(for: layer) : normalizedFrame(for: layer),
            startCropAmount: cameraCropAmount,
            startCropPosition: cameraCropPosition
        )
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard dragMode == nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        cursor(at: location).set()
    }

    override func mouseExited(with event: NSEvent) {
        guard dragMode == nil else { return }
        NSCursor.arrow.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode else { return }

        let location = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(
            x: (location.x - dragMode.startPoint.x) / max(1, canvasFrame.width),
            y: (location.y - dragMode.startPoint.y) / max(1, canvasFrame.height)
        )

        var frame = dragMode.startFrame
        switch dragMode.kind {
        case .move:
            NSCursor.closedHand.set()
            frame.origin.x += delta.x
            frame.origin.y += delta.y
        case .resize(let anchor):
            anchor.cursor.set()
            frame = SceneLayerResizing.resized(
                frame,
                delta: delta,
                anchor: anchor,
                aspectRatio: resizeAspectRatio(for: dragMode.layer)
            )
        case .cropMove:
            NSCursor.closedHand.set()
            updateCameraCrop(movingFrom: dragMode, to: location)
            return
        case .cropResize(let anchor):
            anchor.cursor.set()
            updateCameraCrop(resizingFrom: dragMode, anchor: anchor, to: location)
            return
        }

        setLocalFrame(frame, for: dragMode.layer)

        if let onSceneLayoutChanged {
            onSceneLayoutChanged(sceneLayout)
        } else {
            onLayerFrameChanged?(dragMode.layer, sceneLayout.frame(for: dragMode.layer))
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
        invalidateResizeCursorRects()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    private func layer(at point: CGPoint) -> SceneLayerKind? {
        for layer in SceneLayoutProjection.frontToBackOrder(for: sceneLayout) where enabledSources.contains(layer.source) {
            if frame(for: layer).contains(point) {
                return layer
            }
        }
        return nil
    }

    private func resizeHit(at point: CGPoint) -> (SceneLayerKind, ResizeAnchor)? {
        guard !isCameraCropEditingEnabled else { return nil }
        guard enabledSources.contains(selectedLayer.source),
              let anchor = resizeAnchor(at: point, in: interactiveFrame(for: selectedLayer)) else {
            return nil
        }
        return (selectedLayer, anchor)
    }

    private func cursor(at point: CGPoint) -> NSCursor {
        if isCameraCropEditingEnabled,
           enabledSources.contains(.camera),
           let mode = cameraCropDragMode(at: point) {
            return cursor(for: mode)
        }
        if let (_, anchor) = resizeHit(at: point) {
            return anchor.cursor
        }
        guard canvasFrame.contains(point) else { return .arrow }
        if layer(at: point) != nil {
            return .openHand
        }
        return .arrow
    }

    private func cursor(for mode: DragMode.Kind) -> NSCursor {
        switch mode {
        case .cropMove:
            return .openHand
        case .cropResize(let anchor), .resize(let anchor):
            return anchor.cursor
        case .move:
            return .openHand
        }
    }

    private func applySceneFrames() {
        performWithoutUIAnimation {
            let hasScreen = enabledSources.contains(.screen)
            let hasCamera = enabledSources.contains(.camera)

            screenPreview.isHidden = !hasScreen
            cameraPreview.isHidden = !hasCamera
            safeZoneOverlay.frame = canvasFrame
            updateSafeZoneOverlayVisibility()
            selectionOverlay.isHidden = false
            selectionOverlay.frame = bounds

            if hasScreen {
                screenPreview.frame = denormalized(sceneLayout.screenFrame, in: canvasFrame)
                applyCanvasMask(to: screenPreview)
                applySourceShape(to: screenPreview)
            } else {
                screenPreview.layer?.mask = nil
            }
            if hasCamera {
                cameraPreview.frame = denormalized(sceneLayout.cameraFrame, in: canvasFrame)
                applyCanvasMask(to: cameraPreview)
                applySourceShape(to: cameraPreview)
            } else {
                cameraPreview.layer?.mask = nil
            }

            updateOutlineOverlay()
            updateSelectionOverlay()
        }
    }

    private func setLocalFrame(_ frame: CGRect, for layer: SceneLayerKind) {
        let frame = clamped(frame)
        performWithoutUIAnimation {
            switch layer {
            case .screen:
                sceneLayout.screenFrame = frame
                screenPreview.frame = denormalized(frame, in: canvasFrame)
                applyCanvasMask(to: screenPreview)
                applySourceShape(to: screenPreview)
            case .camera:
                sceneLayout.cameraFrame = frame
                cameraPreview.frame = denormalized(frame, in: canvasFrame)
                applyCanvasMask(to: cameraPreview)
                applySourceShape(to: cameraPreview)
            }
            updateOutlineOverlay()
            updateSelectionOverlay()
        }
        invalidateResizeCursorRects()
        needsDisplay = true
    }

    private func invalidateResizeCursorRects() {
        window?.invalidateCursorRects(for: self)
    }

    private func applyCanvasMask(to view: NSView) {
        guard let layer = view.layer else { return }
        let mask = (view === screenPreview) ? screenCanvasMask : cameraCanvasMask
        let canvasInViewCoords = NSRect(
            x: canvasFrame.minX - view.frame.minX,
            y: canvasFrame.minY - view.frame.minY,
            width: canvasFrame.width,
            height: canvasFrame.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = view.bounds
        if view === cameraPreview {
            let visibleRect = canvasInViewCoords.intersection(view.bounds)
            let radius = sourceCornerRadius(for: visibleRect)
            mask.path = CGPath(roundedRect: visibleRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        } else {
            mask.path = CGPath(rect: canvasInViewCoords, transform: nil)
        }
        if layer.mask !== mask {
            layer.mask = mask
        }
        CATransaction.commit()
    }

    private func applySourceShape(to view: NSView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if view === cameraPreview {
            view.layer?.cornerRadius = sourceCornerRadius(for: view.bounds)
            view.layer?.cornerCurve = .continuous
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        } else {
            view.layer?.cornerRadius = 0
            view.layer?.borderWidth = 0
        }
        CATransaction.commit()
    }

    private func sourceCornerRadius(for rect: CGRect) -> CGFloat {
        guard !rect.isEmpty else { return 0 }
        return min(18, max(8, min(rect.width, rect.height) * 0.08))
    }

    private func updateOutlineOverlay() {
        let hasScreen = enabledSources.contains(.screen)
        let hasCamera = enabledSources.contains(.camera)
        outlineOverlay.frame = bounds
        outlineOverlay.canvasFrame = canvasFrame
        var frames: [NSRect] = []
        if hasScreen { frames.append(screenPreview.frame) }
        if hasCamera { frames.append(cameraPreview.frame) }
        outlineOverlay.sourceFrames = frames
    }

    private func frame(for layer: SceneLayerKind) -> NSRect {
        switch layer {
        case .screen:
            return screenPreview.frame
        case .camera:
            return cameraPreview.frame
        }
    }

    private func normalizedFrame(for layer: SceneLayerKind) -> CGRect {
        sceneLayout.frame(for: layer)
    }

    private func normalizedInteractiveFrame(for layer: SceneLayerKind) -> CGRect {
        normalized(interactiveFrame(for: layer), in: canvasFrame)
    }

    private func denormalized(_ frame: CGRect, in canvas: NSRect) -> NSRect {
        SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(frame, in: canvas, origin: .lowerLeft),
            in: canvas,
            padding: canvasPadding
        )
    }

    private func normalized(_ frame: NSRect, in canvas: NSRect) -> CGRect {
        CGRect(
            x: (frame.minX - canvas.minX) / max(1, canvas.width),
            y: (frame.minY - canvas.minY) / max(1, canvas.height),
            width: frame.width / max(1, canvas.width),
            height: frame.height / max(1, canvas.height)
        )
    }

    private func resizeAnchor(at point: CGPoint, in frame: NSRect) -> ResizeAnchor? {
        resizeTargets(for: frame).first { $0.1.contains(point) }?.0
    }

    private func resizeHandles(for frame: NSRect) -> [ResizeAnchor: NSRect] {
        let size: CGFloat = 18
        let half = size / 2
        return [
            .topLeft: NSRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size),
            .topRight: NSRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size),
            .bottomLeft: NSRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size),
            .bottomRight: NSRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)
        ]
    }

    private func resizeTargets(for frame: NSRect) -> [(ResizeAnchor, NSRect)] {
        resizeHandles(for: frame).map { ($0.key, $0.value) } + edgeHitAreas(for: frame).map { ($0.key, $0.value) }
    }

    private func resizeAspectRatio(for layer: SceneLayerKind) -> CGFloat? {
        switch layer {
        case .screen:
            return screenSourceAspectRatio / captureLayout.aspectRatio
        case .camera:
            return nil
        }
    }

    private func edgeGrips(for frame: NSRect) -> [ResizeAnchor: NSRect] {
        [
            .top: NSRect(x: frame.midX - 14, y: frame.maxY - 2, width: 28, height: 4),
            .bottom: NSRect(x: frame.midX - 14, y: frame.minY - 2, width: 28, height: 4),
            .left: NSRect(x: frame.minX - 2, y: frame.midY - 14, width: 4, height: 28),
            .right: NSRect(x: frame.maxX - 2, y: frame.midY - 14, width: 4, height: 28)
        ]
    }

    private func edgeHitAreas(for frame: NSRect) -> [ResizeAnchor: NSRect] {
        let thickness: CGFloat = 12
        let half = thickness / 2
        return [
            .top: NSRect(x: frame.minX, y: frame.maxY - half, width: frame.width, height: thickness),
            .bottom: NSRect(x: frame.minX, y: frame.minY - half, width: frame.width, height: thickness),
            .left: NSRect(x: frame.minX - half, y: frame.minY, width: thickness, height: frame.height),
            .right: NSRect(x: frame.maxX - half, y: frame.minY, width: thickness, height: frame.height)
        ]
    }

    private func clamped(_ frame: CGRect) -> CGRect {
        SceneLayerResizing.clamped(frame)
    }

    private func applyCanvasBackgroundStyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvasBackgroundLayer.colors = canvasBackgroundStyle.previewColors
        canvasBackgroundLayer.locations = canvasBackgroundStyle.previewLocations
        canvasBackgroundLayer.startPoint = CGPoint(x: 0.08, y: 0.02)
        canvasBackgroundLayer.endPoint = CGPoint(x: 0.92, y: 1)
        canvasBackgroundLayer.backgroundColor = canvasBackgroundStyle.solidCGColor
        CATransaction.commit()
    }

    private func applyLayerOrder() {
        for (index, kind) in sceneLayout.layerOrder.enumerated() {
            let zPosition = CGFloat(index)
            switch kind {
            case .screen:
                screenPreview.layer?.zPosition = zPosition
            case .camera:
                cameraPreview.layer?.zPosition = zPosition
            }
        }
        safeZoneOverlay.layer?.zPosition = CGFloat(sceneLayout.layerOrder.count + 1)
        selectionOverlay.layer?.zPosition = CGFloat(sceneLayout.layerOrder.count + 2)
    }

    private func updateSafeZoneOverlayVisibility() {
        let showsSocialSafeZone = captureLayout == .vertical && socialSafeZoneOverlay != .none
        safeZoneOverlay.isHidden = !showsRuleOfThirdsOverlay && !showsSocialSafeZone
    }

    private func updateSelectionOverlay() {
        selectionOverlay.isCropMode = isCameraCropEditingEnabled && selectedLayer == .camera
        guard enabledSources.contains(selectedLayer.source), !canvasFrame.isEmpty else {
            selectionOverlay.selectionFrame = nil
            selectionOverlay.sourceFrame = nil
            return
        }
        selectionOverlay.frame = bounds
        if isCameraCropEditingEnabled && selectedLayer == .camera {
            selectionOverlay.sourceFrame = frame(for: .camera)
            selectionOverlay.selectionFrame = cameraCropFrame()
        } else {
            selectionOverlay.sourceFrame = nil
            selectionOverlay.selectionFrame = interactiveFrame(for: selectedLayer)
        }
    }

    private func cameraCropDragMode(at point: CGPoint) -> DragMode.Kind? {
        let cropFrame = cameraCropFrame()
        if let anchor = resizeAnchor(at: point, in: cropFrame) {
            return .cropResize(anchor)
        }
        if cropFrame.contains(point) {
            return .cropMove
        }
        return nil
    }

    private func interactiveFrame(for layer: SceneLayerKind) -> NSRect {
        let sourceFrame = frame(for: layer)
        guard !canvasFrame.isEmpty else { return sourceFrame }
        let visibleFrame = sourceFrame.intersection(canvasFrame)
        return visibleFrame.isEmpty ? sourceFrame : visibleFrame
    }

    private func updateCameraCrop(movingFrom dragMode: DragMode, to location: CGPoint) {
        let cameraFrame = frame(for: .camera)
        guard cameraFrame.width > 0, cameraFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        let delta = CGPoint(
            x: location.x - dragMode.startPoint.x,
            y: location.y - dragMode.startPoint.y
        )
        let moved = clampedCameraCropFrame(
            CGRect(
                x: startCrop.minX + delta.x,
                y: startCrop.minY + delta.y,
                width: startCrop.width,
                height: startCrop.height
            ),
            in: cameraFrame
        )
        applyCameraCropFrame(moved, in: cameraFrame)
    }

    private func updateCameraCrop(resizingFrom dragMode: DragMode, anchor: ResizeAnchor, to location: CGPoint) {
        let cameraFrame = frame(for: .camera)
        guard cameraFrame.width > 0, cameraFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        let delta = CGPoint(
            x: location.x - dragMode.startPoint.x,
            y: location.y - dragMode.startPoint.y
        )
        applyCameraCropFrame(resizedCameraCropFrame(startCrop, delta: delta, anchor: anchor, in: cameraFrame), in: cameraFrame)
    }

    private func resizedCameraCropFrame(
        _ crop: CGRect,
        delta: CGPoint,
        anchor: ResizeAnchor,
        in cameraFrame: CGRect
    ) -> CGRect {
        var minX = crop.minX
        var maxX = crop.maxX
        var minY = crop.minY
        var maxY = crop.maxY

        if anchor.resizesLeftEdge { minX += delta.x }
        if anchor.resizesRightEdge { maxX += delta.x }
        if anchor.resizesBottomEdge { minY += delta.y }
        if anchor.resizesTopEdge { maxY += delta.y }

        let currentWidth = max(0.0001, crop.width)
        let currentHeight = max(0.0001, crop.height)
        let widthScale = max(0.0001, maxX - minX) / currentWidth
        let heightScale = max(0.0001, maxY - minY) / currentHeight
        let scale: CGFloat
        if anchor.resizesHorizontalEdgeOnly {
            scale = widthScale
        } else if anchor.resizesVerticalEdgeOnly {
            scale = heightScale
        } else {
            scale = abs(widthScale - 1) >= abs(heightScale - 1) ? widthScale : heightScale
        }

        let cropAspectRatio = max(0.01, cameraFrame.width / cameraFrame.height)
        let minWidth = cameraFrame.width * minimumCropScale
        let minHeight = cameraFrame.height * minimumCropScale
        var width = min(cameraFrame.width, max(minWidth, crop.width * scale))
        var height = width / cropAspectRatio
        if height > cameraFrame.height {
            height = cameraFrame.height
            width = height * cropAspectRatio
        }
        if height < minHeight {
            height = minHeight
            width = height * cropAspectRatio
        }

        let x: CGFloat
        if anchor.resizesLeftEdge {
            x = crop.maxX - width
        } else if anchor.resizesRightEdge {
            x = crop.minX
        } else {
            x = crop.midX - width / 2
        }

        let y: CGFloat
        if anchor.resizesBottomEdge {
            y = crop.maxY - height
        } else if anchor.resizesTopEdge {
            y = crop.minY
        } else {
            y = crop.midY - height / 2
        }

        return clampedCameraCropFrame(CGRect(x: x, y: y, width: width, height: height), in: cameraFrame)
    }

    private func applyCameraCropFrame(_ crop: CGRect, in cameraFrame: CGRect) {
        let scale = min(
            crop.width / max(1, cameraFrame.width),
            crop.height / max(1, cameraFrame.height)
        )
        let amount = CGPoint(
            x: clampedCropAmount(1 - scale),
            y: clampedCropAmount(1 - scale)
        )
        let position = CGPoint(
            x: clampedCropPosition((crop.midX - cameraFrame.midX) / max(0.0001, (cameraFrame.width - crop.width) / 2)),
            y: clampedCropPosition((crop.midY - cameraFrame.midY) / max(0.0001, (cameraFrame.height - crop.height) / 2))
        )
        updateCameraCropDraft(amount: amount, position: position)
    }

    func beginCameraCropEditing() {
        cameraCropDraftAmount = cameraCropAmount
        cameraCropDraftPosition = cameraCropPosition
        selectedLayer = .camera
        isCameraCropEditingEnabled = true
    }

    func commitCameraCropEditing() {
        guard isCameraCropEditingEnabled else { return }
        let amount = activeCameraCropAmount
        let position = activeCameraCropPosition
        isCameraCropEditingEnabled = false
        cameraCropDraftAmount = nil
        cameraCropDraftPosition = nil
        cameraCropAmount = amount
        cameraCropPosition = position
        onCameraCropChanged?(amount, position)
    }

    func cancelCameraCropEditing() {
        cameraCropDraftAmount = nil
        cameraCropDraftPosition = nil
        isCameraCropEditingEnabled = false
    }

    func updateCameraCropDraft(amount: CGPoint? = nil, position: CGPoint? = nil) {
        guard isCameraCropEditingEnabled else { return }
        cameraCropDraftAmount = amount ?? activeCameraCropAmount
        cameraCropDraftPosition = position ?? activeCameraCropPosition
        updateSelectionOverlay()
        invalidateResizeCursorRects()
    }

    private var activeCameraCropAmount: CGPoint {
        cameraCropDraftAmount ?? cameraCropAmount
    }

    private var activeCameraCropPosition: CGPoint {
        cameraCropDraftPosition ?? cameraCropPosition
    }

    private func syncPreviewCrop() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cameraPreview.sourceCropAmount = isCameraCropEditingEnabled ? .zero : cameraCropAmount
        cameraPreview.sourceCropPosition = isCameraCropEditingEnabled ? .zero : cameraCropPosition
        CATransaction.commit()
    }

    private func cameraCropFrame() -> CGRect {
        cameraCropFrame(amount: activeCameraCropAmount, position: activeCameraCropPosition)
    }

    private func cameraCropFrame(amount: CGPoint, position: CGPoint) -> CGRect {
        let cameraFrame = frame(for: .camera)
        guard cameraFrame.width > 0, cameraFrame.height > 0 else { return cameraFrame }
        let scale = max(
            minimumCropScale,
            min(1, min(1 - clampedCropAmount(amount.x), 1 - clampedCropAmount(amount.y)))
        )
        return CGRect(
            x: cameraFrame.midX - cameraFrame.width * scale / 2
                + clampedCropPosition(position.x) * cameraFrame.width * (1 - scale) / 2,
            y: cameraFrame.midY - cameraFrame.height * scale / 2
                + clampedCropPosition(position.y) * cameraFrame.height * (1 - scale) / 2,
            width: cameraFrame.width * scale,
            height: cameraFrame.height * scale
        )
    }

    private func clampedCameraCropFrame(_ crop: CGRect, in cameraFrame: CGRect) -> CGRect {
        let width = min(cameraFrame.width, max(1, crop.width))
        let height = min(cameraFrame.height, max(1, crop.height))
        return CGRect(
            x: min(max(cameraFrame.minX, crop.minX), cameraFrame.maxX - width),
            y: min(max(cameraFrame.minY, crop.minY), cameraFrame.maxY - height),
            width: width,
            height: height
        )
    }

    private func clampedCropAmount(_ amount: CGFloat) -> CGFloat {
        min(0.75, max(0, amount))
    }

    private func clampedCropPosition(_ position: CGFloat) -> CGFloat {
        min(1, max(-1, position))
    }
}

@MainActor
final class SourceOutlineView: NSView {
    var sourceFrames: [NSRect] = [] { didSet { needsDisplay = true } }
    var canvasFrame: NSRect = .zero { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !sourceFrames.isEmpty, !canvasFrame.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let outsideCanvas = NSBezierPath(rect: bounds)
        outsideCanvas.append(NSBezierPath(rect: canvasFrame).reversed)
        outsideCanvas.addClip()

        NSColor.white.withAlphaComponent(0.4).setStroke()
        for rect in sourceFrames where !rect.isEmpty {
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            let pattern: [CGFloat] = [4, 3]
            path.setLineDash(pattern, count: 2, phase: 0)
            path.stroke()
        }
    }
}

private struct DragMode {
    enum Kind {
        case move
        case resize(ResizeAnchor)
        case cropMove
        case cropResize(ResizeAnchor)

        var isResize: Bool {
            switch self {
            case .resize:
                return true
            case .move, .cropMove, .cropResize:
                return false
            }
        }
    }

    let kind: Kind
    let layer: SceneLayerKind
    let startPoint: CGPoint
    let startFrame: CGRect
    let startCropAmount: CGPoint
    let startCropPosition: CGPoint
}

private extension ResizeAnchor {
    var cursor: NSCursor {
        switch self {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return .stageDiagonalResizeNWSE
        case .topRight, .bottomLeft:
            return .stageDiagonalResizeNESW
        }
    }
}

private extension NSCursor {
    static let stageDiagonalResizeNWSE = diagonalResizeCursor(
        start: CGPoint(x: 6, y: 18),
        end: CGPoint(x: 18, y: 6)
    )

    static let stageDiagonalResizeNESW = diagonalResizeCursor(
        start: CGPoint(x: 6, y: 6),
        end: CGPoint(x: 18, y: 18)
    )

    static func diagonalResizeCursor(start: CGPoint, end: CGPoint) -> NSCursor {
        let size = CGSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        drawDiagonalResizeGlyph(start: start, end: end, strokeColor: .black, lineWidth: 4)
        drawDiagonalResizeGlyph(start: start, end: end, strokeColor: .white, lineWidth: 2)

        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    static func drawDiagonalResizeGlyph(start: CGPoint, end: CGPoint, strokeColor: NSColor, lineWidth: CGFloat) {
        strokeColor.setStroke()

        let body = NSBezierPath()
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.lineWidth = lineWidth
        body.move(to: start)
        body.line(to: end)
        body.stroke()

        drawArrowHead(at: start, toward: end, strokeColor: strokeColor, lineWidth: lineWidth)
        drawArrowHead(at: end, toward: start, strokeColor: strokeColor, lineWidth: lineWidth)
    }

    static func drawArrowHead(at tip: CGPoint, toward otherPoint: CGPoint, strokeColor: NSColor, lineWidth: CGFloat) {
        let dx = tip.x - otherPoint.x
        let dy = tip.y - otherPoint.y
        let length = max(1, hypot(dx, dy))
        let unit = CGPoint(x: dx / length, y: dy / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let base = CGPoint(x: tip.x - unit.x * 6, y: tip.y - unit.y * 6)
        let wing: CGFloat = 4

        let head = NSBezierPath()
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.lineWidth = lineWidth
        head.move(to: CGPoint(x: base.x + perpendicular.x * wing, y: base.y + perpendicular.y * wing))
        head.line(to: tip)
        head.line(to: CGPoint(x: base.x - perpendicular.x * wing, y: base.y - perpendicular.y * wing))
        head.stroke()
    }
}

@MainActor
private final class SceneSelectionOverlayView: NSView {
    var selectionFrame: NSRect? {
        didSet { needsDisplay = true }
    }
    var sourceFrame: NSRect? {
        didSet { needsDisplay = true }
    }
    var isCropMode = false {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let frame = selectionFrame else { return }

        if isCropMode, let sourceFrame {
            drawCropShade(sourceFrame: sourceFrame, cropFrame: frame)
        }

        let strokeColor = isCropMode ? NSColor.systemYellow : Brand.primary
        strokeColor.setStroke()
        let outerPath = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
        outerPath.lineWidth = isCropMode ? 2 : 1.5
        outerPath.stroke()

        if isCropMode {
            drawCropGrid(in: frame)
        }

        strokeColor.setFill()
        for grip in edgeGrips(for: frame).values {
            NSBezierPath(roundedRect: grip, xRadius: 2.5, yRadius: 2.5).fill()
        }
        for handle in resizeHandles(for: frame).values {
            NSBezierPath(roundedRect: handle, xRadius: 3, yRadius: 3).fill()
            NSColor.black.withAlphaComponent(0.9).setStroke()
            let handleBorder = NSBezierPath(roundedRect: handle.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            handleBorder.lineWidth = 1
            handleBorder.stroke()
        }
    }

    private func drawCropShade(sourceFrame: NSRect, cropFrame: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill()
        let shade = NSBezierPath(rect: sourceFrame)
        shade.append(NSBezierPath(rect: cropFrame).reversed)
        shade.fill()
    }

    private func drawCropGrid(in frame: NSRect) {
        NSColor.white.withAlphaComponent(0.42).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = frame.minX + frame.width * fraction
            grid.move(to: NSPoint(x: x, y: frame.minY))
            grid.line(to: NSPoint(x: x, y: frame.maxY))

            let y = frame.minY + frame.height * fraction
            grid.move(to: NSPoint(x: frame.minX, y: y))
            grid.line(to: NSPoint(x: frame.maxX, y: y))
        }
        grid.stroke()
    }

    private func resizeHandles(for frame: NSRect) -> [ResizeAnchor: NSRect] {
        let size: CGFloat = 12
        let half = size / 2
        return [
            .topLeft: NSRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size),
            .topRight: NSRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size),
            .bottomLeft: NSRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size),
            .bottomRight: NSRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)
        ]
    }

    private func edgeGrips(for frame: NSRect) -> [ResizeAnchor: NSRect] {
        [
            .top: NSRect(x: frame.midX - 18, y: frame.maxY - 2.5, width: 36, height: 5),
            .bottom: NSRect(x: frame.midX - 18, y: frame.minY - 2.5, width: 36, height: 5),
            .left: NSRect(x: frame.minX - 2.5, y: frame.midY - 18, width: 5, height: 36),
            .right: NSRect(x: frame.maxX - 2.5, y: frame.midY - 18, width: 5, height: 36)
        ]
    }

}

@MainActor
private final class SafeZoneOverlayView: NSView {
    var showsRuleOfThirdsOverlay = false {
        didSet { needsDisplay = true }
    }

    var captureLayout: CaptureLayout = .vertical {
        didSet { needsDisplay = true }
    }

    var socialSafeZoneOverlay: SocialVideoSafeZone = .none {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if captureLayout == .vertical,
           let margins = socialSafeZoneOverlay.margins {
            drawSafeZone(margins: margins, title: socialSafeZoneOverlay.displayName)
        }

        guard showsRuleOfThirdsOverlay else { return }
        drawRuleOfThirds()
    }

    private func drawRuleOfThirds() {
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = bounds.minX + bounds.width * fraction
            grid.move(to: NSPoint(x: x, y: bounds.minY))
            grid.line(to: NSPoint(x: x, y: bounds.maxY))

            let y = bounds.minY + bounds.height * fraction
            grid.move(to: NSPoint(x: bounds.minX, y: y))
            grid.line(to: NSPoint(x: bounds.maxX, y: y))
        }
        grid.stroke()
    }

    private func drawSafeZone(margins: VideoSafeZoneMargins, title: String) {
        let topHeight = bounds.height * margins.top
        let bottomHeight = bounds.height * margins.bottom
        let leftWidth = bounds.width * margins.left
        let rightWidth = bounds.width * margins.right

        let topRect = CGRect(x: bounds.minX, y: bounds.maxY - topHeight, width: bounds.width, height: topHeight)
        let bottomRect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bottomHeight)
        let leftRect = CGRect(x: bounds.minX + leftWidth == bounds.minX ? bounds.minX : bounds.minX,
                              y: bounds.minY + bottomHeight,
                              width: leftWidth,
                              height: bounds.height - topHeight - bottomHeight)
        let rightRect = CGRect(x: bounds.maxX - rightWidth,
                               y: bounds.minY + bottomHeight,
                               width: rightWidth,
                               height: bounds.height - topHeight - bottomHeight)
        let safeRect = CGRect(
            x: bounds.minX + leftWidth,
            y: bounds.minY + bottomHeight,
            width: max(0, bounds.width - leftWidth - rightWidth),
            height: max(0, bounds.height - topHeight - bottomHeight)
        )

        NSColor.black.withAlphaComponent(0.58).setFill()
        [topRect, bottomRect, leftRect, rightRect].forEach { NSBezierPath(rect: $0).fill() }

        let mint = NSColor(red: 0.09, green: 1.0, blue: 0.65, alpha: 1)
        mint.setStroke()
        let safePath = NSBezierPath(roundedRect: safeRect.insetBy(dx: 0.75, dy: 0.75), xRadius: 8, yRadius: 8)
        safePath.lineWidth = 1.75
        safePath.lineCapStyle = .butt
        safePath.setLineDash([6, 4], count: 2, phase: 0)
        safePath.stroke()

        drawCornerTick(at: NSPoint(x: safeRect.minX, y: safeRect.maxY), corner: .topLeft, color: mint)
        drawCornerTick(at: NSPoint(x: safeRect.maxX, y: safeRect.maxY), corner: .topRight, color: mint)
        drawCornerTick(at: NSPoint(x: safeRect.minX, y: safeRect.minY), corner: .bottomLeft, color: mint)
        drawCornerTick(at: NSPoint(x: safeRect.maxX, y: safeRect.minY), corner: .bottomRight, color: mint)

        drawPlatformChip(title: title, in: safeRect)

        if topRect.height > 22 {
            drawRegionHint("UI overlay", in: topRect, alignment: .center)
        }
        if rightRect.width > 26 {
            drawRegionHint("Actions", in: rightRect, alignment: .vertical)
        }
        if bottomRect.height > 22 {
            drawRegionHint("Caption · CTA", in: bottomRect, alignment: .center)
        }
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func drawCornerTick(at point: NSPoint, corner: Corner, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        let length: CGFloat = 14
        switch corner {
        case .topLeft:
            path.move(to: NSPoint(x: point.x, y: point.y - length))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x + length, y: point.y))
        case .topRight:
            path.move(to: NSPoint(x: point.x - length, y: point.y))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x, y: point.y - length))
        case .bottomLeft:
            path.move(to: NSPoint(x: point.x, y: point.y + length))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x + length, y: point.y))
        case .bottomRight:
            path.move(to: NSPoint(x: point.x - length, y: point.y))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x, y: point.y + length))
        }
        path.stroke()
    }

    private func drawPlatformChip(title: String, in safeRect: CGRect) {
        let label = "\(title) safe area"
        let font = NSFont.systemFont(ofSize: 10.5, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: 0.5
        ]
        let attributed = NSAttributedString(string: label.uppercased(), attributes: attributes)
        let labelSize = attributed.size()
        let chipWidth = labelSize.width + 18
        let chipHeight = labelSize.height + 8
        let x = safeRect.minX + 8
        let y = safeRect.maxY - chipHeight - 8
        let rect = CGRect(x: x, y: y, width: chipWidth, height: chipHeight)
        let mint = NSColor(red: 0.09, green: 1.0, blue: 0.65, alpha: 1)

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: rect, xRadius: chipHeight / 2, yRadius: chipHeight / 2).fill()
        mint.withAlphaComponent(0.65).setStroke()
        let chipStroke = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: (chipHeight - 1.5) / 2, yRadius: (chipHeight - 1.5) / 2)
        chipStroke.lineWidth = 1
        chipStroke.stroke()

        // Mint leading dot to anchor the chip visually.
        let dotRadius: CGFloat = 3
        let dotRect = CGRect(x: rect.minX + 9 - dotRadius, y: rect.midY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        mint.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        attributed.draw(at: NSPoint(x: rect.minX + 9 + dotRadius + 6, y: rect.minY + 4))
    }

    private enum HintAlignment { case center, vertical }

    private func drawRegionHint(_ text: String, in rect: CGRect, alignment: HintAlignment) {
        let font = NSFont.systemFont(ofSize: 10.5, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.78),
            .kern: 0.8
        ]
        let attributed = NSAttributedString(string: text.uppercased(), attributes: attributes)
        let labelSize = attributed.size()

        switch alignment {
        case .center:
            let x = rect.midX - labelSize.width / 2
            let y = rect.midY - labelSize.height / 2
            attributed.draw(at: NSPoint(x: x, y: y))
        case .vertical:
            NSGraphicsContext.current?.saveGraphicsState()
            let context = NSGraphicsContext.current?.cgContext
            context?.translateBy(x: rect.midX, y: rect.midY)
            context?.rotate(by: -.pi / 2)
            let x = -labelSize.width / 2
            let y = -labelSize.height / 2
            attributed.draw(at: NSPoint(x: x, y: y))
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }
}

@MainActor
final class ScreenPreviewView: NSView {
    private let placeholderLayer = CALayer()
    private let imageLayer = CALayer()
    private let label = NSTextField(labelWithString: "SCREEN PREVIEW")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
        layer?.actions = noResizeActions

        placeholderLayer.backgroundColor = Brand.card.withAlphaComponent(0.96).cgColor
        placeholderLayer.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        placeholderLayer.borderWidth = 1
        placeholderLayer.actions = noResizeActions
        layer?.addSublayer(placeholderLayer)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.backgroundColor = .clear
        imageLayer.actions = noResizeActions
        layer?.addSublayer(imageLayer)

        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.9)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        label.layer?.cornerRadius = 6
        label.layer?.masksToBounds = true
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -28)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        syncLayerFrames()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncLayerFrames()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        syncLayerFrames()
    }

    private func syncLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.frame = bounds
        placeholderLayer.cornerRadius = min(10, min(bounds.width, bounds.height) / 8)
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    func setImage(_ image: CGImage) {
        placeholderLayer.isHidden = true
        imageLayer.contents = image
        label.isHidden = true
    }

    func setMessage(_ message: String) {
        placeholderLayer.isHidden = false
        imageLayer.contents = nil
        label.isHidden = false
        label.stringValue = message
    }
}

@MainActor
final class CameraPreviewView: NSView {
    private let label = NSTextField(labelWithString: "CAMERA")
    private let imageLayer = CALayer()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private var sourceAspectRatio: CGFloat = SceneLayout.cameraAspectRatio {
        didSet { syncPreviewLayerFrame() }
    }
    var sourceCropAmount: CGPoint = .zero {
        didSet { syncPreviewLayerFrame() }
    }
    var sourceCropPosition: CGPoint = .zero {
        didSet { syncPreviewLayerFrame() }
    }
    var hasPreviewContent: Bool { previewLayer != nil || sampleBufferLayer != nil || imageLayer.contents != nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
        layer?.actions = noResizeActions

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.backgroundColor = .clear
        imageLayer.actions = noResizeActions
        layer?.addSublayer(imageLayer)

        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        syncPreviewLayerFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncPreviewLayerFrame()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        syncPreviewLayerFrame()
    }

    private func syncPreviewLayerFrame() {
        let contentFrame = SourceCropGeometry.sourceFrame(
            sourceAspectRatio: sourceAspectRatio,
            bounds: bounds,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = contentFrame
        sampleBufferLayer?.frame = contentFrame
        imageLayer.frame = contentFrame
        CATransaction.commit()
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer?.removeFromSuperlayer()
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        previewLayer = layer
        imageLayer.contents = nil
        sourceAspectRatio = Self.sourceAspectRatio(for: layer) ?? SceneLayout.cameraAspectRatio
        layer.videoGravity = .resizeAspectFill
        layer.actions = noResizeActions
        syncPreviewLayerFrame()
        self.layer?.insertSublayer(layer, at: 0)
        label.isHidden = true
    }

    func setPreviewImage(_ image: CGImage) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = image
        sourceAspectRatio = CGFloat(image.width) / max(1, CGFloat(image.height))
        syncPreviewLayerFrame()
        label.isHidden = true
    }

    func enqueuePreviewSampleBuffer(_ sampleBuffer: CMSampleBuffer, width: Int, height: Int) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        imageLayer.contents = nil
        if sampleBufferLayer == nil {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspectFill
            layer.actions = noResizeActions
            layer.backgroundColor = NSColor.black.cgColor
            sampleBufferLayer = layer
            self.layer?.insertSublayer(layer, at: 0)
        }
        sourceAspectRatio = CGFloat(width) / max(1, CGFloat(height))
        syncPreviewLayerFrame()
        guard let sampleBufferLayer else { return }
        if #available(macOS 15.0, *) {
            let renderer = sampleBufferLayer.sampleBufferRenderer
            if renderer.status == .failed {
                renderer.flush()
            }
            if renderer.isReadyForMoreMediaData {
                renderer.enqueue(sampleBuffer)
            }
        } else {
            if sampleBufferLayer.status == .failed {
                sampleBufferLayer.flush()
            }
            if sampleBufferLayer.isReadyForMoreMediaData {
                sampleBufferLayer.enqueue(sampleBuffer)
            }
        }
        label.isHidden = true
    }

    func setMessage(_ message: String) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = nil
        label.isHidden = false
        label.stringValue = message
    }

    private static func sourceAspectRatio(for layer: AVCaptureVideoPreviewLayer) -> CGFloat? {
        layer.session?.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .compactMap { device in
                let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                guard dimensions.width > 0, dimensions.height > 0 else { return nil }
                return CGFloat(dimensions.width) / CGFloat(dimensions.height)
            }
            .first
    }
}
