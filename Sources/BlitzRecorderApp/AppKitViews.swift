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
    private let cameraShadowLayer = CALayer()
    private let canvasBackgroundLayer = CALayer()
    private var renderedBackgroundKey: (style: CanvasBackgroundStyle, width: Int, height: Int)?
    private var backgroundAnimationTimer: Timer?
    private let backgroundAnimationQueue = DispatchQueue(label: "blitzrecorder.preview-background", qos: .userInitiated)
    private var backgroundAnimationStart: CFTimeInterval = 0
    private var isRenderingAnimatedFrame = false
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
    private var screenCropDraft: CGRect?
    private let resizeHandleOutset: CGFloat = 14
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var selectedLayer: SceneLayerKind = .camera {
        didSet {
            updateSelectionOverlay()
            invalidateResizeCursorRects()
        }
    }
    var allowsLayerInteraction: Bool = true {
        didSet {
            guard oldValue != allowsLayerInteraction else { return }
            if !allowsLayerInteraction {
                dragMode = nil
                NSCursor.arrow.set()
            }
            updateSelectionOverlay()
            invalidateResizeCursorRects()
        }
    }
    var allowsCameraCropInteraction: Bool = true {
        didSet {
            guard oldValue != allowsCameraCropInteraction else { return }
            if !allowsCameraCropInteraction {
                dragMode = nil
                isCameraCropEditingEnabled = false
                cameraCropDraftAmount = nil
                cameraCropDraftPosition = nil
                NSCursor.arrow.set()
            }
            updateSelectionOverlay()
            invalidateResizeCursorRects()
        }
    }
    var onLayerFrameChanged: ((SceneLayerKind, CGRect) -> Void)?
    var onSceneLayoutChanged: ((SceneLayout) -> Void)?
    var onLayerSelected: ((SceneLayerKind) -> Void)?
    var onBackgroundSelected: (() -> Void)?
    var onCropToolbarFrameChanged: ((CGRect?) -> Void)?
    var onScreenLayerFrameChanged: ((CGRect?) -> Void)?
    var onCameraCropChanged: ((CGPoint, CGPoint) -> Void)?
    var onScreenCropChanged: ((CGRect?) -> Void)?
    var renderedCanvasAspectRatio: CGFloat {
        guard canvasFrame.height > 0 else { return 0 }
        return canvasFrame.width / canvasFrame.height
    }
    var renderedCanvasFrameForTesting: CGRect { canvasFrame }
    var renderedScreenFrameForTesting: CGRect { screenPreview.frame }
    var renderedCameraFrameForTesting: CGRect { cameraPreview.frame }
    var renderedCameraShadowOpacityForTesting: Float { cameraShadowLayer.shadowOpacity }
    var renderedCameraContentMasksToBoundsForTesting: Bool { cameraPreview.layer?.masksToBounds == true }
    var renderedSelectionFrameForTesting: CGRect? { selectionOverlay.selectionFrame }
    var renderedSelectionShowsResizeHandlesForTesting: Bool { selectionOverlay.showsResizeHandles }
    var renderedCropToolbarFrameForTesting: CGRect? { cropToolbarFrame }
    private var cropToolbarFrame: CGRect? {
        didSet {
            guard oldValue != cropToolbarFrame else { return }
            onCropToolbarFrameChanged?(cropToolbarFrame)
        }
    }
    private var screenLayerFrame: CGRect? {
        didSet {
            guard oldValue != screenLayerFrame else { return }
            onScreenLayerFrameChanged?(screenLayerFrame)
        }
    }

    var isCameraCropEditingEnabled: Bool = false {
        didSet {
            syncPreviewCrop()
            if !canvasFrame.isEmpty {
                applySceneFrames()
            }
            updateSelectionOverlay()
            invalidateResizeCursorRects()
        }
    }

    var isScreenCropEditingEnabled: Bool = false {
        didSet {
            if !canvasFrame.isEmpty {
                applySceneFrames()
            }
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

    var screenCrop: CGRect? {
        didSet {
            if !isScreenCropEditingEnabled {
                screenCropDraft = screenCrop
            }
            updateSelectionOverlay()
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
            guard oldValue != canvasBackgroundStyle else { return }
            renderedBackgroundKey = nil
            refreshCanvasBackground()
        }
    }

    var canvasBackgroundAnimated: Bool = false {
        didSet {
            guard oldValue != canvasBackgroundAnimated else { return }
            updateBackgroundAnimation()
        }
    }

    var isBackgroundLayerSelected: Bool = false {
        didSet {
            guard oldValue != isBackgroundLayerSelected else { return }
            updateCanvasSelectionAffordance()
            updateSelectionOverlay()
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

    var cameraContentMode: CameraContentMode = .fill {
        didSet {
            cameraPreview.contentMode = cameraContentMode.renderContentMode
            if !canvasFrame.isEmpty {
                applySceneFrames()
            }
        }
    }

    var cameraFramePadding: CGFloat = 0 {
        didSet {
            if !canvasFrame.isEmpty {
                applySceneFrames()
            }
            invalidateResizeCursorRects()
        }
    }

    var cameraShadowEnabled: Bool = false {
        didSet {
            if !canvasFrame.isEmpty {
                applySceneFrames()
            }
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
        layer?.masksToBounds = true

        canvasBackgroundLayer.backgroundColor = canvasBackgroundStyle.appearance.solidCGColor
        canvasBackgroundLayer.contentsGravity = .resize
        canvasBackgroundLayer.zPosition = -1
        canvasBackgroundLayer.cornerRadius = 8
        canvasBackgroundLayer.masksToBounds = true
        canvasBackgroundLayer.borderWidth = 1.5
        canvasBackgroundLayer.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        canvasBackgroundLayer.actions = [
            "frame": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull(),
            "borderColor": NSNull(),
            "borderWidth": NSNull(),
            "cornerRadius": NSNull()
        ]
        layer?.addSublayer(canvasBackgroundLayer)
        cameraShadowLayer.actions = [
            "frame": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "shadowPath": NSNull(),
            "shadowOpacity": NSNull()
        ]
        cameraShadowLayer.shadowColor = NSColor.black.cgColor
        cameraShadowLayer.shadowRadius = 18
        cameraShadowLayer.shadowOffset = CGSize(width: 0, height: -8)
        cameraShadowLayer.shadowOpacity = 0
        layer?.addSublayer(cameraShadowLayer)

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
            canvasFrame = fittedCanvas(in: bounds.insetBy(dx: resizeHandleOutset + 12, dy: resizeHandleOutset + 12))
            canvasBackgroundLayer.frame = canvasFrame
            refreshCanvasBackground()
            applyLayerOrder()
            applySceneFrames()
            updateSelectionOverlay()
        }
        if canvasBackgroundAnimated {
            updateBackgroundAnimation()
        }
        invalidateResizeCursorRects()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundAnimation()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !canvasFrame.isEmpty else { return }

        if isScreenCropEditingEnabled, enabledSources.contains(.screen) {
            let frame = screenCropFrame()
            let sourceFrame = screenCropSourceFrame()
            let moveRect = frame.insetBy(dx: 12, dy: 12)
            if moveRect.width > 0, moveRect.height > 0 {
                addCursorRect(moveRect, cursor: .openHand)
            }
            for (anchor, rect) in resizeTargets(for: frame, constrainedTo: sourceFrame) {
                addCursorRect(rect, cursor: anchor.cursor)
            }
            return
        }

        if allowsCameraCropInteraction, isCameraCropEditingEnabled, enabledSources.contains(.camera) {
            let frame = frame(for: .camera)
            let sourceFrame = cameraCropSourceFrame()
            let moveRect = frame.insetBy(dx: 12, dy: 12)
            if moveRect.width > 0, moveRect.height > 0 {
                addCursorRect(moveRect, cursor: .openHand)
            }
            for (anchor, rect) in resizeTargets(for: frame, constrainedTo: sourceFrame) {
                addCursorRect(rect, cursor: anchor.cursor)
            }
            return
        }

        guard allowsLayerInteraction else { return }

        for layer in SceneLayoutProjection.frontToBackOrder(for: sceneLayout) where enabledSources.contains(layer.source) {
            guard canEditLayerFrame(layer) else { continue }
            let visibleFrame = interactiveFrame(for: layer)
            let moveRect = visibleFrame.insetBy(dx: 12, dy: 12)
            if moveRect.width > 0, moveRect.height > 0 {
                addCursorRect(moveRect, cursor: .openHand)
            }
            guard layer == selectedLayer else { continue }
            for (anchor, rect) in cornerResizeTargets(for: selectionFrame(for: layer)) {
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

        if isScreenCropEditingEnabled,
           enabledSources.contains(.screen),
           let mode = screenCropDragMode(at: location) {
            selectedLayer = .screen
            onLayerSelected?(.screen)
            dragMode = DragMode(
                kind: mode,
                layer: .screen,
                startPoint: location,
                startFrame: screenCropFrame(),
                startCropAmount: cameraCropAmount,
                startCropPosition: cameraCropPosition
            )
            cursor(for: mode).set()
            needsDisplay = true
            return
        }

        if allowsCameraCropInteraction,
           isCameraCropEditingEnabled,
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

        guard allowsLayerInteraction else {
            dragMode = nil
            return
        }

        if let (layer, anchor) = resizeHit(at: location) {
            selectedLayer = layer
            onLayerSelected?(layer)
            dragMode = DragMode(
                kind: .resize(anchor),
                layer: layer,
                startPoint: location,
                startFrame: normalizedSelectionFrame(for: layer),
                startCropAmount: cameraCropAmount,
                startCropPosition: cameraCropPosition
            )
            anchor.cursor.set()
            needsDisplay = true
            return
        }

        guard let layer = layer(at: location) else {
            if canvasFrame.contains(location) {
                isBackgroundLayerSelected = true
                onBackgroundSelected?()
                dragMode = nil
                needsDisplay = true
            }
            return
        }
        isBackgroundLayerSelected = false
        let wasSelected = layer == selectedLayer
        selectedLayer = layer
        onLayerSelected?(layer)
        guard canEditLayerFrame(layer) else {
            dragMode = nil
            needsDisplay = true
            return
        }
        let frame = selectionFrame(for: layer)
        let mode: DragMode.Kind
        if wasSelected, let anchor = cornerResizeAnchor(at: location, in: frame) {
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
            startFrame: mode.isResize ? normalizedSelectionFrame(for: layer) : normalizedFrame(for: layer),
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

        switch dragMode.kind {
        case .screenCropMove, .screenCropResize:
            guard isScreenCropEditingEnabled else {
                self.dragMode = nil
                return
            }
        case .cropMove, .cropResize:
            guard allowsCameraCropInteraction else {
                self.dragMode = nil
                return
            }
        case .move, .resize:
            guard allowsLayerInteraction else {
                self.dragMode = nil
                return
            }
        }

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
                aspectRatio: dragMode.startFrame.width / max(0.01, dragMode.startFrame.height)
            )
        case .cropMove:
            NSCursor.closedHand.set()
            updateCameraCrop(movingFrom: dragMode, to: location)
            return
        case .cropResize(let anchor):
            anchor.cursor.set()
            updateCameraCrop(resizingFrom: dragMode, anchor: anchor, to: location)
            return
        case .screenCropMove:
            NSCursor.closedHand.set()
            updateScreenCrop(movingFrom: dragMode, to: location)
            return
        case .screenCropResize(let anchor):
            anchor.cursor.set()
            updateScreenCrop(resizingFrom: dragMode, anchor: anchor, to: location)
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
        PreviewStageEditing.layer(
            at: point,
            sceneLayout: sceneLayout,
            enabledSources: enabledSources,
            frameForLayer: frame(for:)
        )
    }

    private func resizeHit(at point: CGPoint) -> (SceneLayerKind, ResizeAnchor)? {
        guard canEditLayerFrame(selectedLayer),
              let anchor = cornerResizeAnchor(at: point, in: selectionFrame(for: selectedLayer)) else {
            return nil
        }
        return (selectedLayer, anchor)
    }

    private func cursor(at point: CGPoint) -> NSCursor {
        if isScreenCropEditingEnabled,
           enabledSources.contains(.screen),
           let mode = screenCropDragMode(at: point) {
            return cursor(for: mode)
        }
        if allowsCameraCropInteraction,
           isCameraCropEditingEnabled,
           enabledSources.contains(.camera),
           let mode = cameraCropDragMode(at: point) {
            return cursor(for: mode)
        }
        guard allowsLayerInteraction else { return .arrow }
        if let (_, anchor) = resizeHit(at: point) {
            return anchor.cursor
        }
        if let layer = layer(at: point), canEditLayerFrame(layer) {
            return .openHand
        }
        return .arrow
    }

    private func cursor(for mode: DragMode.Kind) -> NSCursor {
        switch mode {
        case .cropMove:
            return .openHand
        case .screenCropMove:
            return .openHand
        case .screenCropResize(let anchor), .cropResize(let anchor), .resize(let anchor):
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
            selectionOverlay.canvasClip = canvasFrame

            if hasScreen {
                screenPreview.frame = isScreenCropEditingEnabled ? screenCropSourceFrame() : projectedFrame(for: .screen, in: canvasFrame)
                applyCanvasMask(to: screenPreview)
                applySourceShape(to: screenPreview)
            } else {
                screenPreview.layer?.mask = nil
            }
            if hasCamera {
                cameraPreview.frame = isCameraCropEditingEnabled ? cameraCropSourceFrame() : projectedFrame(for: .camera, in: canvasFrame)
                applyCanvasMask(to: cameraPreview)
                applySourceShape(to: cameraPreview)
            } else {
                cameraPreview.layer?.mask = nil
                applyCameraShadow(frame: .zero, cornerRadius: 0)
            }

            updateOutlineOverlay()
            updateSelectionOverlay()
            screenLayerFrame = hasScreen ? screenPreview.frame : nil
        }
    }

    private func setLocalFrame(_ frame: CGRect, for layer: SceneLayerKind) {
        let frame = clamped(frame)
        performWithoutUIAnimation {
            switch layer {
            case .screen:
                sceneLayout.screenFrame = frame
                screenPreview.frame = projectedFrame(for: .screen, in: canvasFrame)
                applyCanvasMask(to: screenPreview)
                applySourceShape(to: screenPreview)
            case .camera:
                sceneLayout.cameraFrame = frame
                cameraPreview.frame = projectedFrame(for: .camera, in: canvasFrame)
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
            if isCameraCropEditingEnabled {
                if layer.mask !== nil {
                    layer.mask = nil
                }
                CATransaction.commit()
                return
            }
            let visibleRect = canvasInViewCoords.intersection(view.bounds)
            let radius = sourceMaskCornerRadius(for: view, visibleRect: visibleRect)
            mask.path = sourceMaskPath(for: visibleRect, radius: radius)
        } else if isScreenCropEditingEnabled {
            if layer.mask !== nil {
                layer.mask = nil
            }
            CATransaction.commit()
            return
        } else {
            let visibleRect = canvasInViewCoords.intersection(view.bounds)
            let radius = sourceMaskCornerRadius(for: view, visibleRect: visibleRect)
            mask.path = sourceMaskPath(for: visibleRect, radius: radius)
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
            let isFullscreen = isFullscreenCameraPreview
            let paddedRadius = SceneLayoutProjection.sourceCornerRadius(for: view.bounds, canvasPadding: canvasPadding)
            let radius = paddedRadius > 0 || (!isFullscreen && !isFullWidthCameraPreview)
                ? (paddedRadius > 0 ? paddedRadius : sourceCornerRadius(for: view.bounds))
                : 0
            view.layer?.cornerRadius = radius
            view.layer?.cornerCurve = .continuous
            view.layer?.borderWidth = radius > 0 ? 1 : 0
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            view.layer?.shadowOpacity = 0
            view.layer?.shadowPath = nil
            applyCameraShadow(frame: view.frame, cornerRadius: radius)
        } else {
            let radius = SceneLayoutProjection.sourceCornerRadius(for: view.bounds, canvasPadding: canvasPadding)
            view.layer?.cornerRadius = radius
            view.layer?.cornerCurve = .continuous
            view.layer?.borderWidth = radius > 0 ? 1 : 0
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        }
        CATransaction.commit()
    }

    private func applyCameraShadow(frame: NSRect, cornerRadius: CGFloat) {
        guard cameraShadowEnabled,
              !isCameraCropEditingEnabled,
              !isFullscreenCameraPreview,
              !frame.isEmpty else {
            cameraShadowLayer.shadowOpacity = 0
            cameraShadowLayer.shadowPath = nil
            return
        }
        cameraShadowLayer.frame = frame
        cameraShadowLayer.shadowOpacity = 0.38
        cameraShadowLayer.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: frame.size),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    private func sourceMaskPath(for rect: CGRect, radius: CGFloat) -> CGPath {
        guard radius > 0 else {
            return CGPath(rect: rect, transform: nil)
        }
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func sourceMaskCornerRadius(for view: NSView, visibleRect: CGRect) -> CGFloat {
        let paddedRadius = SceneLayoutProjection.sourceCornerRadius(for: visibleRect, canvasPadding: canvasPadding)
        guard paddedRadius <= 0,
              view === cameraPreview,
              !isFullscreenCameraPreview,
              !isFullWidthCameraPreview else {
            return paddedRadius
        }
        return sourceCornerRadius(for: visibleRect)
    }

    private func sourceCornerRadius(for rect: CGRect) -> CGFloat {
        guard !rect.isEmpty else { return 0 }
        return min(18, max(8, min(rect.width, rect.height) * 0.08))
    }

    private func updateOutlineOverlay() {
        let geometry = renderGeometry(in: canvasFrame)
        outlineOverlay.frame = bounds
        outlineOverlay.canvasFrame = canvasFrame
        outlineOverlay.sourceFrames = geometry.activeLayerOrder
            .filter { hasLiveContent(for: $0) }
            .map { frame(for: $0) }
    }

    private func hasLiveContent(for layer: SceneLayerKind) -> Bool {
        switch layer {
        case .screen:
            return screenPreview.hasPreviewContent
        case .camera:
            return cameraPreview.hasPreviewContent
        }
    }

    private func frame(for layer: SceneLayerKind) -> NSRect {
        switch layer {
        case .screen:
            return screenPreview.frame
        case .camera:
            return cameraPreview.frame
        }
    }

    private func canEditLayerFrame(_ layer: SceneLayerKind) -> Bool {
        guard allowsLayerInteraction,
              enabledSources.contains(layer.source),
              !isCameraCropEditingEnabled,
              !isScreenCropEditingEnabled else {
            return false
        }
        return enabledSources.contains(.screen) && enabledSources.contains(.camera)
    }

    private func normalizedFrame(for layer: SceneLayerKind) -> CGRect {
        sceneLayout.frame(for: layer)
    }

    private func normalizedSelectionFrame(for layer: SceneLayerKind) -> CGRect {
        normalized(selectionFrame(for: layer), in: canvasFrame)
    }

    private func projectedFrame(for layer: SceneLayerKind, in canvas: NSRect) -> NSRect {
        let geometry = renderGeometry(in: canvas)
        guard layer == .camera,
              cameraContentMode == .fit,
              !isCameraCropEditingEnabled else {
            return geometry.targetRect(for: layer)
        }
        return geometry.sourceFrame(
            for: .camera,
            sourceAspectRatio: cameraPreview.currentSourceAspectRatio,
            sourceCropAmount: .zero,
            sourceCropPosition: .zero
        )
    }

    private func renderGeometry(in canvas: NSRect) -> SceneRenderGeometry {
        SceneRenderGeometry(
            canvas: canvas,
            scene: RecordingScene(
                enabledSources: enabledSources,
                sceneLayout: sceneLayout,
                screenSourceGeometry: ScreenSourceGeometry(
                    normalizedCrop: screenCrop,
                    sourceAspectRatio: screenSourceAspectRatio
                ),
                cameraCropAmount: cameraCropAmount,
                cameraCropPosition: cameraCropPosition,
                canvasBackgroundStyle: canvasBackgroundStyle,
                canvasPadding: canvasPadding,
                cameraContentMode: cameraContentMode,
                cameraFramePadding: cameraFramePadding,
                cameraShadowEnabled: cameraShadowEnabled
            ),
            origin: .lowerLeft
        )
    }

    private var isFullscreenCameraPreview: Bool {
        renderGeometry(in: canvasFrame).isFullCanvasFrame(for: .camera)
    }

    private var isFullWidthCameraPreview: Bool {
        renderGeometry(in: canvasFrame).isFullCanvasWidth(for: .camera)
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
        PreviewStageEditing.resizeAnchor(at: point, in: frame)
    }

    private func cornerResizeAnchor(at point: CGPoint, in frame: NSRect) -> ResizeAnchor? {
        PreviewStageEditing.cornerResizeAnchor(at: point, in: frame)
    }

    private func resizeHandles(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [ResizeAnchor: NSRect] {
        PreviewStageEditing.resizeHandles(for: frame, constrainedTo: constraint)
    }

    private func resizeTargets(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [(ResizeAnchor, NSRect)] {
        PreviewStageEditing.resizeTargets(for: frame, constrainedTo: constraint)
    }

    private func cornerResizeTargets(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [(ResizeAnchor, NSRect)] {
        PreviewStageEditing.cornerResizeTargets(for: frame, constrainedTo: constraint)
    }

    private func edgeGrips(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [ResizeAnchor: NSRect] {
        PreviewStageEditing.edgeGrips(for: frame, constrainedTo: constraint)
    }

    private func edgeHitAreas(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [ResizeAnchor: NSRect] {
        PreviewStageEditing.edgeHitAreas(for: frame, constrainedTo: constraint)
    }

    private func clamped(_ frame: CGRect) -> CGRect {
        SceneLayerResizing.clamped(frame)
    }

    private func refreshCanvasBackground() {
        guard !canvasBackgroundAnimated || !canvasBackgroundStyle.supportsBackgroundAnimation else { return }
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 2
        canvasBackgroundLayer.contentsScale = scale
        let width = Int((canvasBackgroundLayer.bounds.width * scale).rounded(.up))
        let height = Int((canvasBackgroundLayer.bounds.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return }
        if let key = renderedBackgroundKey,
           key.style == canvasBackgroundStyle, key.width == width, key.height == height {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let appearance = canvasBackgroundStyle.appearance
        canvasBackgroundLayer.backgroundColor = appearance.solidCGColor
        canvasBackgroundLayer.contents = appearance.renderCGImage(pixelWidth: width, pixelHeight: height)
        CATransaction.commit()
        renderedBackgroundKey = (canvasBackgroundStyle, width, height)
    }


    private func updateBackgroundAnimation() {
        let shouldAnimate = canvasBackgroundAnimated
            && canvasBackgroundStyle.supportsBackgroundAnimation
            && window != nil
            && !canvasBackgroundLayer.bounds.isEmpty
        if shouldAnimate {
            guard backgroundAnimationTimer == nil else { return }
            backgroundAnimationStart = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.renderAnimatedBackgroundFrame()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            backgroundAnimationTimer = timer
            renderAnimatedBackgroundFrame()
        } else {
            backgroundAnimationTimer?.invalidate()
            backgroundAnimationTimer = nil
            renderedBackgroundKey = nil
            refreshCanvasBackground()
        }
    }

    private func renderAnimatedBackgroundFrame() {
        guard canvasBackgroundAnimated, canvasBackgroundStyle.supportsBackgroundAnimation, !isRenderingAnimatedFrame else { return }
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 2
        canvasBackgroundLayer.contentsScale = scale
        let width = Int((canvasBackgroundLayer.bounds.width * scale).rounded(.up))
        let height = Int((canvasBackgroundLayer.bounds.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return }
        let style = canvasBackgroundStyle
        let loop = CanvasAppearance.animationLoopDuration
        let phase = ((CACurrentMediaTime() - backgroundAnimationStart) / loop).truncatingRemainder(dividingBy: 1)
        isRenderingAnimatedFrame = true
        backgroundAnimationQueue.async { [weak self] in
            let image = style.appearance.renderCGImage(pixelWidth: width, pixelHeight: height, animationPhase: phase)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRenderingAnimatedFrame = false
                guard self.canvasBackgroundAnimated,
                      self.canvasBackgroundStyle == style,
                      self.canvasBackgroundStyle.supportsBackgroundAnimation else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.canvasBackgroundLayer.contents = image
                CATransaction.commit()
            }
        }
    }

    private func updateCanvasSelectionAffordance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isBackgroundLayerSelected {
            canvasBackgroundLayer.borderColor = Self.backgroundSelectionColor.cgColor
            canvasBackgroundLayer.borderWidth = 2
        } else {
            canvasBackgroundLayer.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
            canvasBackgroundLayer.borderWidth = 1.5
        }
        CATransaction.commit()
    }

    private static let backgroundSelectionColor = NSColor(srgbRed: 0.09, green: 1.0, blue: 0.65, alpha: 0.95)

    private func applyLayerOrder() {
        for (index, kind) in sceneLayout.layerOrder.enumerated() {
            let zPosition = CGFloat(index)
            switch kind {
            case .screen:
                screenPreview.layer?.zPosition = zPosition
            case .camera:
                cameraPreview.layer?.zPosition = zPosition
                cameraShadowLayer.zPosition = zPosition - 0.5
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
        if isBackgroundLayerSelected {
            selectionOverlay.isCropMode = false
            selectionOverlay.showsResizeHandles = false
            selectionOverlay.selectionFrame = nil
            selectionOverlay.sourceFrame = nil
            selectionOverlay.canvasClip = nil
            cropToolbarFrame = nil
            return
        }

        if isScreenCropEditingEnabled {
            selectionOverlay.isCropMode = true
            selectionOverlay.showsResizeHandles = true
            guard enabledSources.contains(.screen), !canvasFrame.isEmpty else {
                selectionOverlay.selectionFrame = nil
                selectionOverlay.sourceFrame = nil
                selectionOverlay.canvasClip = nil
                cropToolbarFrame = nil
                return
            }
            selectionOverlay.frame = bounds
            selectionOverlay.canvasClip = canvasFrame
            selectionOverlay.sourceFrame = screenCropSourceFrame()
            let cropFrame = screenCropFrame()
            selectionOverlay.selectionFrame = cropFrame
            cropToolbarFrame = cropToolbarFrame(above: cropFrame)
            return
        }

        let isCropMode = allowsCameraCropInteraction && isCameraCropEditingEnabled && selectedLayer == .camera
        guard allowsLayerInteraction || isCropMode else {
            selectionOverlay.isCropMode = false
            selectionOverlay.showsResizeHandles = false
            selectionOverlay.selectionFrame = nil
            selectionOverlay.sourceFrame = nil
            selectionOverlay.canvasClip = nil
            cropToolbarFrame = nil
            return
        }
        selectionOverlay.isCropMode = isCropMode
        guard enabledSources.contains(selectedLayer.source), !canvasFrame.isEmpty else {
            selectionOverlay.showsResizeHandles = false
            selectionOverlay.selectionFrame = nil
            selectionOverlay.sourceFrame = nil
            selectionOverlay.canvasClip = nil
            cropToolbarFrame = nil
            return
        }
        selectionOverlay.frame = bounds
        selectionOverlay.canvasClip = canvasFrame
        if isCropMode {
            selectionOverlay.showsResizeHandles = true
            selectionOverlay.sourceFrame = cameraCropSourceFrame()
            let cropFrame = cameraCropFrame()
            selectionOverlay.selectionFrame = cropFrame
            cropToolbarFrame = cropToolbarFrame(above: cropFrame)
        } else {
            selectionOverlay.showsResizeHandles = canEditLayerFrame(selectedLayer)
            selectionOverlay.sourceFrame = nil
            selectionOverlay.selectionFrame = interactiveFrame(for: selectedLayer)
            cropToolbarFrame = nil
        }
    }

    private func cropToolbarFrame(above frame: NSRect) -> NSRect {
        let size = NSSize(width: 206, height: 40)
        let x = min(bounds.maxX - size.width - 8, max(bounds.minX + 8, frame.midX - size.width / 2))
        let preferredY = frame.maxY + 8
        let fallbackY = frame.maxY - size.height - 8
        let y = preferredY + size.height <= bounds.maxY - 8 ? preferredY : fallbackY
        return NSRect(
            x: x,
            y: max(bounds.minY + 8, y),
            width: size.width,
            height: size.height
        )
    }

    private func cameraCropDragMode(at point: CGPoint) -> DragMode.Kind? {
        PreviewStageEditing.cameraCropDragMode(
            at: point,
            cropFrame: cameraCropFrame(),
            allowsCameraCropInteraction: allowsCameraCropInteraction
        )
    }

    private func screenCropDragMode(at point: CGPoint) -> DragMode.Kind? {
        PreviewStageEditing.screenCropDragMode(
            at: point,
            cropFrame: screenCropFrame(),
            constrainedTo: screenCropSourceFrame()
        )
    }

    private func interactiveFrame(for layer: SceneLayerKind) -> NSRect {
        let sourceFrame = frame(for: layer)
        guard !canvasFrame.isEmpty else { return sourceFrame }
        let visibleFrame = sourceFrame.intersection(canvasFrame)
        return visibleFrame.isEmpty ? sourceFrame : visibleFrame
    }

    private func selectionFrame(for layer: SceneLayerKind) -> NSRect {
        frame(for: layer)
    }

    private func updateCameraCrop(movingFrom dragMode: DragMode, to location: CGPoint) {
        let cropGeometry = cameraCropGeometry()
        guard cropGeometry.sourceFrame.width > 0, cropGeometry.sourceFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        let delta = CGPoint(
            x: location.x - dragMode.startPoint.x,
            y: location.y - dragMode.startPoint.y
        )
        applyCameraCropControl(for: cropGeometry.movedCropFrame(startCrop, delta: delta), using: cropGeometry)
    }

    private func updateCameraCrop(resizingFrom dragMode: DragMode, anchor: ResizeAnchor, to location: CGPoint) {
        let cropGeometry = cameraCropGeometry()
        guard cropGeometry.sourceFrame.width > 0, cropGeometry.sourceFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        let delta = CGPoint(
            x: location.x - dragMode.startPoint.x,
            y: location.y - dragMode.startPoint.y
        )
        applyCameraCropControl(
            for: cropGeometry.resizedCropFrame(startCrop, delta: delta, anchor: anchor),
            using: cropGeometry
        )
    }

    private func applyCameraCropControl(for crop: CGRect, using cropGeometry: CameraCropGeometry) {
        guard let control = cropGeometry.control(for: crop) else { return }
        updateCameraCropDraft(amount: control.amount, position: control.position)
    }

    private func updateScreenCrop(movingFrom dragMode: DragMode, to location: CGPoint) {
        let sourceFrame = screenCropSourceFrame()
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
        let delta = CGPoint(x: location.x - dragMode.startPoint.x, y: location.y - dragMode.startPoint.y)
        let moved = dragMode.startFrame.offsetBy(dx: delta.x, dy: delta.y)
        updateScreenCropDraft(screenCropFrame: clampedScreenCropFrame(moved, in: sourceFrame))
    }

    private func updateScreenCrop(resizingFrom dragMode: DragMode, anchor: ResizeAnchor, to location: CGPoint) {
        let sourceFrame = screenCropSourceFrame()
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
        let delta = CGPoint(x: location.x - dragMode.startPoint.x, y: location.y - dragMode.startPoint.y)
        let resized = resizedScreenCropFrame(dragMode.startFrame, delta: delta, anchor: anchor, in: sourceFrame)
        updateScreenCropDraft(screenCropFrame: resized)
    }

    func beginCameraCropEditing() {
        guard allowsCameraCropInteraction else { return }
        cameraCropDraftAmount = cameraCropAmount
        cameraCropDraftPosition = cameraCropPosition
        selectedLayer = .camera
        isCameraCropEditingEnabled = true
    }

    func beginScreenCropEditing(crop: CGRect?) {
        screenCropDraft = crop ?? defaultScreenCropDraft()
        selectedLayer = .screen
        isCameraCropEditingEnabled = false
        isScreenCropEditingEnabled = true
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

    func commitScreenCropEditing() {
        guard isScreenCropEditingEnabled else { return }
        let draft = clampedNormalizedScreenCrop(screenCropDraft ?? CGRect(x: 0, y: 0, width: 1, height: 1))
        isScreenCropEditingEnabled = false
        screenCropDraft = nil
        screenCrop = draft
        onScreenCropChanged?(draft)
    }

    func cancelScreenCropEditing() {
        screenCropDraft = screenCrop
        isScreenCropEditingEnabled = false
    }

    func resetScreenCropDraft() {
        guard isScreenCropEditingEnabled else { return }
        screenCropDraft = defaultScreenCropDraft()
        updateSelectionOverlay()
        invalidateResizeCursorRects()
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
        cameraCropGeometry().cropFrame(amount: amount, position: position)
    }

    private func cameraCropSourceFrame() -> CGRect {
        cameraCropGeometry().sourceFrame
    }

    private func cameraCropGeometry() -> CameraCropGeometry {
        CameraCropGeometry(
            renderGeometry: renderGeometry(in: canvasFrame),
            sourceAspectRatio: cameraPreview.currentSourceAspectRatio
        )
    }

    private func screenCropSourceFrame() -> CGRect {
        let target = projectedFrame(for: .screen, in: canvasFrame)
        guard screenSourceAspectRatio > 0, target.width > 0, target.height > 0 else { return target }
        let targetAspect = target.width / target.height
        if targetAspect > screenSourceAspectRatio {
            let height = target.width / screenSourceAspectRatio
            return CGRect(x: target.minX, y: target.midY - height / 2, width: target.width, height: height)
        }
        let width = target.height * screenSourceAspectRatio
        return CGRect(x: target.midX - width / 2, y: target.minY, width: width, height: target.height)
    }

    private func screenCropFrame() -> CGRect {
        let sourceFrame = screenCropSourceFrame()
        let crop = clampedNormalizedScreenCrop(screenCropDraft ?? screenCrop ?? CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGRect(
            x: sourceFrame.minX + crop.minX * sourceFrame.width,
            y: sourceFrame.minY + (1 - crop.maxY) * sourceFrame.height,
            width: crop.width * sourceFrame.width,
            height: crop.height * sourceFrame.height
        )
    }

    private func defaultScreenCropDraft() -> CGRect {
        let sourceFrame = screenCropSourceFrame()
        let targetFrame = projectedFrame(for: .screen, in: canvasFrame)
        guard sourceFrame.width > 0, sourceFrame.height > 0,
              !targetFrame.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let visibleTarget = targetFrame.intersection(sourceFrame)
        guard !visibleTarget.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return clampedNormalizedScreenCrop(CGRect(
            x: (visibleTarget.minX - sourceFrame.minX) / sourceFrame.width,
            y: 1 - ((visibleTarget.maxY - sourceFrame.minY) / sourceFrame.height),
            width: visibleTarget.width / sourceFrame.width,
            height: visibleTarget.height / sourceFrame.height
        ))
    }

    private func updateScreenCropDraft(screenCropFrame: CGRect) {
        let sourceFrame = screenCropSourceFrame()
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
        screenCropDraft = clampedNormalizedScreenCrop(CGRect(
            x: (screenCropFrame.minX - sourceFrame.minX) / sourceFrame.width,
            y: 1 - ((screenCropFrame.maxY - sourceFrame.minY) / sourceFrame.height),
            width: screenCropFrame.width / sourceFrame.width,
            height: screenCropFrame.height / sourceFrame.height
        ))
        updateSelectionOverlay()
        invalidateResizeCursorRects()
    }

    private func clampedScreenCropFrame(_ frame: CGRect, in sourceFrame: CGRect) -> CGRect {
        let minimumWidth = min(sourceFrame.width, max(12, sourceFrame.width * 0.05))
        let minimumHeight = min(sourceFrame.height, max(12, sourceFrame.height * 0.05))
        let width = min(sourceFrame.width, max(minimumWidth, frame.width))
        let height = min(sourceFrame.height, max(minimumHeight, frame.height))
        let x = min(sourceFrame.maxX - width, max(sourceFrame.minX, frame.minX))
        let y = min(sourceFrame.maxY - height, max(sourceFrame.minY, frame.minY))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func resizedScreenCropFrame(_ frame: CGRect, delta: CGPoint, anchor: ResizeAnchor, in sourceFrame: CGRect) -> CGRect {
        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY
        if anchor.resizesLeftEdge { minX += delta.x }
        if anchor.resizesRightEdge { maxX += delta.x }
        if anchor.resizesBottomEdge { minY += delta.y }
        if anchor.resizesTopEdge { maxY += delta.y }
        return clampedScreenCropFrame(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), in: sourceFrame)
    }

    private func clampedNormalizedScreenCrop(_ crop: CGRect) -> CGRect {
        let crop = crop.standardized
        let x = min(1, max(0, crop.minX))
        let y = min(1, max(0, crop.minY))
        let maxX = min(1, max(x, crop.maxX))
        let maxY = min(1, max(y, crop.maxY))
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
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

        let margin = canvasFrame.insetBy(dx: -SceneSelectionOverlayView.handleRadius,
                                         dy: -SceneSelectionOverlayView.handleRadius)
        let outsideCanvas = NSBezierPath(rect: margin)
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

extension ResizeAnchor {
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

extension NSCursor {
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
    static let handleRadius: CGFloat = 6

    var selectionFrame: NSRect? {
        didSet { needsDisplay = true }
    }
    var sourceFrame: NSRect? {
        didSet { needsDisplay = true }
    }
    var isCropMode = false {
        didSet { needsDisplay = true }
    }
    var showsResizeHandles = true {
        didSet { needsDisplay = true }
    }
    var canvasClip: NSRect? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let frame = selectionFrame else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let canvasClip, !canvasClip.isEmpty else { return }
        let clipRect = canvasClip.insetBy(dx: -Self.handleRadius, dy: -Self.handleRadius)
        NSBezierPath(rect: clipRect).addClip()

        if isCropMode, let sourceFrame {
            drawCropShade(within: canvasClip, cropFrame: frame)
            drawCropSourceOutline(sourceFrame)
        }

        let strokeColor = Brand.primary
        strokeColor.setStroke()
        let outerPath = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
        outerPath.lineWidth = isCropMode ? 2 : 1.5
        if isCropMode {
            outerPath.setLineDash([8, 4], count: 2, phase: 0)
        }
        outerPath.stroke()

        if isCropMode {
            drawCropGrid(in: frame)
        }

        strokeColor.setFill()
        let handleConstraint = isCropMode ? sourceFrame : nil
        if isCropMode {
            for grip in edgeGrips(for: frame, constrainedTo: handleConstraint).values {
                NSBezierPath(roundedRect: grip, xRadius: 2.5, yRadius: 2.5).fill()
            }
        }
        if showsResizeHandles {
            for handle in resizeHandles(for: frame, constrainedTo: handleConstraint).values {
                NSBezierPath(roundedRect: handle, xRadius: 3, yRadius: 3).fill()
                NSColor.black.withAlphaComponent(isCropMode ? 0.72 : 0.9).setStroke()
                let handleBorder = NSBezierPath(roundedRect: handle.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                handleBorder.lineWidth = 1
                handleBorder.stroke()
            }
        }
    }

    private func drawCropShade(within region: NSRect, cropFrame: NSRect) {
        NSColor.black.withAlphaComponent(0.58).setFill()
        let shade = NSBezierPath(rect: region)
        shade.append(NSBezierPath(rect: cropFrame).reversed)
        shade.fill()
    }

    private func drawCropSourceOutline(_ sourceFrame: NSRect) {
        NSColor.white.withAlphaComponent(0.38).setStroke()
        let sourcePath = NSBezierPath(rect: sourceFrame.insetBy(dx: 0.5, dy: 0.5))
        sourcePath.lineWidth = 1
        sourcePath.setLineDash([5, 4], count: 2, phase: 0)
        sourcePath.stroke()
    }

    private func drawCropGrid(in frame: NSRect) {
        NSColor.white.withAlphaComponent(0.40).setStroke()
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

    private func resizeHandles(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [ResizeAnchor: NSRect] {
        let size: CGFloat = 12
        let half = size / 2
        return [
            .topLeft: NSRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size),
            .topRight: NSRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size),
            .bottomLeft: NSRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size),
            .bottomRight: NSRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)
        ].mapValues { constrained($0, to: constraint) }
    }

    private func edgeGrips(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [ResizeAnchor: NSRect] {
        [
            .top: NSRect(x: frame.midX - 18, y: frame.maxY - 2.5, width: 36, height: 5),
            .bottom: NSRect(x: frame.midX - 18, y: frame.minY - 2.5, width: 36, height: 5),
            .left: NSRect(x: frame.minX - 2.5, y: frame.midY - 18, width: 5, height: 36),
            .right: NSRect(x: frame.maxX - 2.5, y: frame.midY - 18, width: 5, height: 36)
        ].mapValues { constrained($0, to: constraint) }
    }

    private func constrained(_ rect: NSRect, to constraint: NSRect?) -> NSRect {
        guard let constraint, !constraint.isEmpty else { return rect }
        let width = min(rect.width, constraint.width)
        let height = min(rect.height, constraint.height)
        let minX = constraint.minX
        let maxX = constraint.maxX - width
        let minY = constraint.minY
        let maxY = constraint.maxY - height
        return NSRect(
            x: min(maxX, max(minX, rect.minX)),
            y: min(maxY, max(minY, rect.minY)),
            width: width,
            height: height
        )
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
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private let label = NSTextField(labelWithString: "SCREEN PREVIEW")

    var hasPreviewContent: Bool { placeholderLayer.isHidden }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = false
        layer?.actions = noResizeActions

        placeholderLayer.backgroundColor = .clear
        placeholderLayer.borderWidth = 0
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
        sampleBufferLayer?.frame = bounds
        CATransaction.commit()
    }

    func setImage(_ image: CGImage) {
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        placeholderLayer.isHidden = true
        imageLayer.contents = image
        label.isHidden = true
    }

    func enqueuePreviewSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        imageLayer.contents = nil
        if sampleBufferLayer == nil {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspectFill
            layer.actions = noResizeActions
            layer.backgroundColor = NSColor.clear.cgColor
            sampleBufferLayer = layer
            self.layer?.insertSublayer(layer, above: placeholderLayer)
            syncLayerFrames()
        }
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
        placeholderLayer.isHidden = true
        label.isHidden = true
    }

    func setMessage(_ message: String) {
        placeholderLayer.isHidden = false
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = nil
        label.isHidden = message.isEmpty
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
    var contentMode: VideoRenderContentMode = .aspectFill {
        didSet { syncPreviewLayerFrame() }
    }
    var hasPreviewContent: Bool { previewLayer != nil || sampleBufferLayer != nil || imageLayer.contents != nil }
    var currentSourceAspectRatio: CGFloat { sourceAspectRatio }

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
        let contentFrame = VideoRenderPlacement(
            kind: .camera,
            targetRect: bounds,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition,
            contentMode: contentMode
        ).sourceFrame(sourceAspectRatio: sourceAspectRatio)
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

    func setPreviewImage(_ image: CGImage, sourceAspectRatio overrideAspectRatio: CGFloat? = nil) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = image
        sourceAspectRatio = overrideAspectRatio ?? CGFloat(image.width) / max(1, CGFloat(image.height))
        syncPreviewLayerFrame()
        label.isHidden = true
    }

    func enqueuePreviewSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        width: Int,
        height: Int,
        sourceAspectRatio overrideAspectRatio: CGFloat? = nil
    ) {
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
        sourceAspectRatio = overrideAspectRatio ?? CGFloat(width) / max(1, CGFloat(height))
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

    func setSourceAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0 else { return }
        sourceAspectRatio = aspectRatio
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

private extension CGRect {
    var isFullCanvasFrame: Bool {
        isAlmostEqual(to: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func isAlmostEqual(to other: CGRect, tolerance: CGFloat = 0.0001) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
