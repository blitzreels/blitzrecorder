import AppKit
import AVFoundation
import QuartzCore

@MainActor
final class PreviewStageView: NSView {
    struct BackgroundRenderKey: Equatable {
        let style: CanvasBackgroundStyle
        let width: Int
        let height: Int
    }

    let screenPreview = ScreenPreviewView()
    let cameraPreview = CameraPreviewView()
    let cameraShadowLayer = CALayer()
    let canvasBackgroundLayer = CALayer()
    var renderedBackgroundKey: BackgroundRenderKey?
    var requestedBackgroundKey: BackgroundRenderKey?
    var cachedRenderGeometry: (request: PreviewStageLayout.RenderRequest, value: SceneRenderGeometry)?
    var cachedCameraCropGeometry: (request: PreviewStageLayout.RenderRequest, aspect: CGFloat, value: CameraCropGeometry)?
    var cachedScreenCropSourceFrame: (request: PreviewStageLayout.RenderRequest, aspect: CGFloat, value: CGRect)?
    var cachedCameraFillFlags: (fullscreen: Bool, fullWidth: Bool)?
    var lastLayoutPassKey: PreviewStagePassKeys.LayoutPassKey?
    var lastScreenShapeKey: PreviewStagePassKeys.SourceShapeKey?
    var lastCameraShapeKey: PreviewStagePassKeys.SourceShapeKey?
    var lastScreenMaskKey: PreviewStagePassKeys.CanvasMaskKey?
    var lastCameraMaskKey: PreviewStagePassKeys.CanvasMaskKey?
    var lastSelectionOverlayKey: PreviewStagePassKeys.SelectionOverlayKey?
    var lastOutlineOverlayKey: PreviewStagePassKeys.OutlineOverlayKey?
    var lastLayerOrder: [SceneLayerKind]?

    typealias LayoutPassKey = PreviewStagePassKeys.LayoutPassKey
    typealias SourceShapeKey = PreviewStagePassKeys.SourceShapeKey
    typealias SelectionOverlayKey = PreviewStagePassKeys.SelectionOverlayKey
    typealias OutlineOverlayKey = PreviewStagePassKeys.OutlineOverlayKey
    typealias CanvasMaskKey = PreviewStagePassKeys.CanvasMaskKey

    var backgroundRenderTimer: Timer?
    var backgroundAnimationTimer: Timer?
    let backgroundAnimationQueue = DispatchQueue(label: "blitzrecorder.preview-background", qos: .userInitiated)
    var backgroundAnimationStart: CFTimeInterval = 0
    var isRenderingAnimatedFrame = false
    let safeZoneOverlay = SafeZoneOverlayView()
    let selectionOverlay = SceneSelectionOverlayView()
    let outlineOverlay = SourceOutlineView()
    let screenCanvasMask = CAShapeLayer()
    let cameraCanvasMask = CAShapeLayer()
    var canvasFrame = NSRect.zero {
        didSet {
            guard oldValue != canvasFrame else { return }
            onCanvasFrameChanged?(canvasFrame)
        }
    }
    var lastDragCursorKind: DragMode.Kind?
    var isApplyingLocalDragFrame = false
    var dragMode: DragMode? {
        didSet {
            if dragMode == nil {
                lastDragCursorKind = nil
            }
        }
    }
    var sceneID: UUID? {
        didSet {
            guard oldValue != sceneID else { return }
            cancelCanvasInteraction()
        }
    }
    var trackingArea: NSTrackingArea?
    var cameraCropDraftAmount: CGPoint?
    var cameraCropDraftPosition: CGPoint?
    var screenCropDraft: CGRect?
    let resizeHandleOutset: CGFloat = 14
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var selectedLayer: SceneLayerKind = .camera {
        didSet {
            guard oldValue != selectedLayer else { return }
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
    var onSceneLayoutEditingEnded: ((SceneLayout) -> Void)?
    var onLayerResizeEnded: ((SceneLayerKind) -> Void)?
    var onLayerSelected: ((SceneLayerKind) -> Void)?
    var onBackgroundSelected: (() -> Void)?
    var onCropToolbarFrameChanged: ((CGRect?) -> Void)?
    var onScreenLayerFrameChanged: ((CGRect?) -> Void)?
    var onCanvasFrameChanged: ((CGRect) -> Void)?
    var onCameraCropChanged: ((CGPoint, CGPoint) -> Void)?
    var onScreenCropChanged: ((CGRect?) -> Void)?
    var onScreenCropPanRequested: (() -> Void)?
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
    var cropToolbarFrame: CGRect? {
        didSet {
            guard oldValue != cropToolbarFrame else { return }
            onCropToolbarFrameChanged?(cropToolbarFrame)
        }
    }
    var screenLayerFrame: CGRect? {
        didSet {
            guard oldValue != screenLayerFrame else { return }
            onScreenLayerFrameChanged?(screenLayerFrame)
        }
    }

    var isCameraCropEditingEnabled: Bool = false {
        didSet {
            guard oldValue != isCameraCropEditingEnabled else { return }
            syncPreviewCrop()
            relayoutCanvasImmediately()
        }
    }

    var isScreenCropEditingEnabled: Bool = false {
        didSet {
            guard oldValue != isScreenCropEditingEnabled else { return }
            relayoutCanvasImmediately()
        }
    }

    var captureLayout: CaptureLayout = .vertical {
        didSet {
            guard oldValue != captureLayout else { return }
            cancelCanvasInteraction()
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

    var screenFillsSceneFrame = false {
        didSet {
            if oldValue != screenFillsSceneFrame {
                needsLayout = true
                needsDisplay = true
            }
        }
    }

    var screenCrop: CGRect? {
        didSet {
            guard oldValue != screenCrop else { return }
            if !isScreenCropEditingEnabled {
                screenCropDraft = screenCrop
            }
            updateSelectionOverlay()
        }
    }

    var cameraCropAmount: CGPoint = .zero {
        didSet {
            guard oldValue != cameraCropAmount else { return }
            if !isCameraCropEditingEnabled {
                cameraPreview.sourceCropAmount = cameraCropAmount
            }
            updateSelectionOverlay()
        }
    }

    var cameraCropPosition: CGPoint = .zero {
        didSet {
            guard oldValue != cameraCropPosition else { return }
            if !isCameraCropEditingEnabled {
                cameraPreview.sourceCropPosition = cameraCropPosition
            }
            updateSelectionOverlay()
        }
    }

    var canvasBackgroundStyle: CanvasBackgroundStyle = .black {
        didSet {
            guard oldValue != canvasBackgroundStyle else { return }
            invalidateCanvasBackgroundRender()
            refreshCanvasBackground()
        }
    }

    var canvasBackgroundAnimated: Bool = false {
        didSet {
            guard oldValue != canvasBackgroundAnimated else { return }
            invalidateCanvasBackgroundRender()
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
            guard oldValue != canvasPadding else { return }
            relayoutCanvasImmediately()
        }
    }

    var screenContentMode: CameraContentMode = .fill {
        didSet {
            guard oldValue != screenContentMode else { return }
            relayoutCanvasImmediately()
        }
    }

    var cameraContentMode: CameraContentMode = .fill {
        didSet {
            guard oldValue != cameraContentMode else { return }
            cameraPreview.contentMode = cameraContentMode.renderContentMode
            relayoutCanvasImmediately()
        }
    }

    var cameraFramePadding: CGFloat = 0 {
        didSet {
            guard oldValue != cameraFramePadding else { return }
            relayoutCanvasImmediately()
        }
    }

    var cameraShadowEnabled: Bool = false {
        didSet {
            guard oldValue != cameraShadowEnabled else { return }
            relayoutCanvasImmediately()
        }
    }

    var showsRuleOfThirdsOverlay: Bool = false {
        didSet {
            guard oldValue != showsRuleOfThirdsOverlay else { return }
            safeZoneOverlay.showsRuleOfThirdsOverlay = showsRuleOfThirdsOverlay
            updateSafeZoneOverlayVisibility()
            safeZoneOverlay.needsDisplay = true
        }
    }

    var socialSafeZoneOverlay: SocialVideoSafeZone = .none {
        didSet {
            guard oldValue != socialSafeZoneOverlay else { return }
            safeZoneOverlay.socialSafeZoneOverlay = socialSafeZoneOverlay
            updateSafeZoneOverlayVisibility()
            safeZoneOverlay.needsDisplay = true
        }
    }

    var enabledSources: Set<CaptureSource> = [] {
        didSet {
            guard oldValue != enabledSources else { return }
            if let dragMode, !enabledSources.contains(dragMode.layer.source) {
                cancelCanvasInteraction()
            }
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
            guard oldValue != sceneLayout else { return }
            if isApplyingLocalDragFrame {
                if oldValue.layerOrder != sceneLayout.layerOrder { applyLayerOrder() }
                return
            }
            if oldValue.layerOrder != sceneLayout.layerOrder { applyLayerOrder() }
            relayoutCanvasImmediately()
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

    override func layout() {
        super.layout()

        let key = layoutPassKey()
        if lastLayoutPassKey == key {
            if canvasBackgroundAnimated {
                updateBackgroundAnimation()
            }
            return
        }
        lastLayoutPassKey = key

        performWithoutUIAnimation {
            canvasFrame = fittedCropEditingCanvas(
                in: bounds.insetBy(dx: resizeHandleOutset + 12, dy: resizeHandleOutset + 12)
            )
            canvasBackgroundLayer.frame = canvasFrame
            refreshCanvasBackground()
            applyLayerOrder()
            applySceneFrames()
        }
        if canvasBackgroundAnimated {
            updateBackgroundAnimation()
        }
        invalidateResizeCursorRects()
    }

    func layoutPassKey() -> LayoutPassKey {
        LayoutPassKey(
            bounds: bounds,
            captureLayout: captureLayout,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled,
            isScreenCropEditingEnabled: isScreenCropEditingEnabled,
            enabledSources: enabledSources,
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
            cameraShadowEnabled: cameraShadowEnabled
        )
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        refreshCanvasBackground()
        invalidateResizeCursorRects()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundAnimation()
    }

    func fittedCropEditingCanvas(in rect: NSRect) -> NSRect {
        let canvas = PreviewStageLayout.fittedCanvas(in: rect, captureLayout: captureLayout)
        guard isCameraCropEditingEnabled, enabledSources.contains(.camera) else { return canvas }
        return PreviewStageLayout.cropEditingCanvas(
            fittedCanvas: canvas,
            in: rect,
            cameraSourceAspectRatio: cameraPreview.currentSourceAspectRatio,
            geometry: renderGeometry(in: canvas)
        )
    }

    func relayoutCanvasImmediately() {
        let key = layoutPassKey()
        if lastLayoutPassKey == key {
            if canvasBackgroundAnimated {
                updateBackgroundAnimation()
            }
            return
        }
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
