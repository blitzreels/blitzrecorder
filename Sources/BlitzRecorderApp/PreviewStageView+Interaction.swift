import AppKit
import QuartzCore

extension PreviewStageView {
    func applySceneFrames() {
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
                let frame = isScreenCropEditingEnabled ? screenCropSourceFrame() : projectedFrame(for: .screen, in: canvasFrame)
                if screenPreview.frame != frame {
                    screenPreview.frame = frame
                }
                applyCanvasMask(to: screenPreview)
                applySourceShape(to: screenPreview)
            } else {
                screenPreview.layer?.mask = nil
                lastScreenMaskKey = nil
                lastScreenShapeKey = nil
            }
            if hasCamera {
                let frame = isCameraCropEditingEnabled ? cameraCropSourceFrame() : projectedFrame(for: .camera, in: canvasFrame)
                if cameraPreview.frame != frame {
                    cameraPreview.frame = frame
                }
                applyCanvasMask(to: cameraPreview)
                applySourceShape(to: cameraPreview)
            } else {
                cameraPreview.layer?.mask = nil
                lastCameraMaskKey = nil
                lastCameraShapeKey = nil
                applyCameraShadow(frame: .zero, cornerRadius: 0)
            }

            updateOutlineOverlay()
            updateSelectionOverlay()
            screenLayerFrame = hasScreen ? screenPreview.frame : nil
        }
    }

    struct LayerFrameUpdate {
        let frame: CGRect
        let layer: SceneLayerKind
    }

    func applyLayerDragFrame(_ frame: CGRect, layer: SceneLayerKind) {
        isApplyingLocalDragFrame = true
        setLocalFrame(.init(frame: frame, layer: layer))
        isApplyingLocalDragFrame = false
        applyDraggedLayerPreview(layer)
        if let onSceneLayoutChanged {
            onSceneLayoutChanged(sceneLayout)
        } else {
            onLayerFrameChanged?(layer, sceneLayout.frame(for: layer))
        }
    }

    func applyDraggedLayerPreview(_ layer: SceneLayerKind) {
        guard !canvasFrame.isEmpty else { return }
        performWithoutUIAnimation {
            let frame = projectedFrame(for: layer, in: canvasFrame)
            if layer == .screen {
                if screenPreview.frame != frame {
                    screenPreview.frame = frame
                }
                screenLayerFrame = frame
            } else {
                if cameraPreview.frame != frame {
                    cameraPreview.frame = frame
                }
            }
            updateOutlineOverlay()
            updateSelectionOverlay()
        }
    }

    func interactionHit(at location: CGPoint) -> PreviewStageEditing.MouseDownHit {
        let screenCropMode = isScreenCropEditingEnabled && enabledSources.contains(.screen)
            ? screenCropDragMode(at: location)
            : nil
        let cameraCropMode = allowsCameraCropInteraction
            && isCameraCropEditingEnabled
            && enabledSources.contains(.camera)
            ? cameraCropDragMode(at: location)
            : nil
        let needsLayerHits = allowsLayerInteraction && screenCropMode == nil && cameraCropMode == nil
        return PreviewStageEditing.mouseDownHit(.init(
            isScreenCropEditingEnabled: isScreenCropEditingEnabled,
            hasScreen: enabledSources.contains(.screen),
            screenCropMode: screenCropMode,
            allowsCameraCropInteraction: allowsCameraCropInteraction,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled,
            hasCamera: enabledSources.contains(.camera),
            cameraCropMode: cameraCropMode,
            allowsLayerInteraction: allowsLayerInteraction,
            resizeHit: needsLayerHits ? resizeHit(at: location) : nil,
            layerAtPoint: needsLayerHits ? layer(at: location) : nil,
            canvasContainsPoint: canvasFrame.contains(location)
        ))
    }

    func setLocalFrame(_ update: LayerFrameUpdate) {
        let frame = SceneLayerResizing.clamped(update.frame)
        sceneLayout.setFrame(frame, for: update.layer)
    }

    func cancelCanvasInteraction() {
        dragMode = nil
        NSCursor.arrow.set()
        if isCameraCropEditingEnabled { cancelCameraCropEditing() }
        if isScreenCropEditingEnabled { cancelScreenCropEditing() }
    }

    func invalidateResizeCursorRects() {
        guard !inLiveResize else { return }
        window?.invalidateCursorRects(for: self)
    }

    func applyCanvasMask(to view: NSView) {
        guard let layer = view.layer else { return }
        let isCamera = view === cameraPreview
        let cropEditing = isCamera ? isCameraCropEditingEnabled : isScreenCropEditingEnabled
        let key = CanvasMaskKey(
            viewFrame: view.frame,
            canvasFrame: canvasFrame,
            cropEditing: cropEditing,
            isCamera: isCamera,
            isFullscreen: isCamera ? isFullscreenCameraPreview : false,
            isFullWidth: isCamera ? isFullWidthCameraPreview : false
        )
        if isCamera {
            if lastCameraMaskKey == key { return }
            lastCameraMaskKey = key
        } else if lastScreenMaskKey == key {
            return
        } else {
            lastScreenMaskKey = key
        }

        let canvasInViewCoords = PreviewStageDrawing.canvasRectInView(
            canvasFrame: canvasFrame,
            viewFrame: view.frame
        )
        let visibleRect = canvasInViewCoords.intersection(view.bounds)
        let radius = cropEditing ? 0 : PreviewStageDrawing.maskCornerRadius(
            visibleRect: visibleRect,
            isCamera: isCamera,
            isFullscreen: isFullscreenCameraPreview,
            isFullWidth: isFullWidthCameraPreview
        )
        let mask = isCamera ? cameraCanvasMask : screenCanvasMask
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = view.bounds
        if cropEditing {
            if layer.mask !== nil {
                layer.mask = nil
            }
            CATransaction.commit()
            return
        }
        mask.path = PreviewStageDrawing.maskPath(for: visibleRect, radius: radius)
        if layer.mask !== mask {
            layer.mask = mask
        }
        CATransaction.commit()
    }

    func applySourceShape(to view: NSView) {
        let isCamera = view === cameraPreview
        let key = SourceShapeKey(
            bounds: view.bounds,
            frame: view.frame,
            isFullscreen: isCamera ? isFullscreenCameraPreview : false,
            isFullWidth: isCamera ? isFullWidthCameraPreview : false,
            cameraShadowEnabled: cameraShadowEnabled,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled
        )
        if isCamera {
            if lastCameraShapeKey == key { return }
            lastCameraShapeKey = key
        } else {
            if lastScreenShapeKey == key { return }
            lastScreenShapeKey = key
        }

        let shape = PreviewStageDrawing.sourceShape(
            isCamera: isCamera,
            bounds: view.bounds,
            isFullscreen: isCamera ? isFullscreenCameraPreview : false,
            isFullWidth: isCamera ? isFullWidthCameraPreview : false
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let layer = view.layer {
            PreviewStageDrawing.apply(shape, to: layer)
            if isCamera {
                layer.shadowOpacity = 0
                layer.shadowPath = nil
                applyCameraShadow(frame: view.frame, cornerRadius: shape.cornerRadius)
            }
        }
        CATransaction.commit()
    }

    func applyCameraShadow(frame: NSRect, cornerRadius: CGFloat) {
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

    func updateOutlineOverlay() {
        let key = OutlineOverlayKey(
            bounds: bounds,
            canvasFrame: canvasFrame,
            screenFrame: screenPreview.frame,
            cameraFrame: cameraPreview.frame,
            layerOrder: sceneLayout.layerOrder,
            hasScreenContent: screenPreview.hasPreviewContent,
            hasCameraContent: cameraPreview.hasPreviewContent
        )
        if lastOutlineOverlayKey == key {
            return
        }
        lastOutlineOverlayKey = key
        let geometry = renderGeometry(in: canvasFrame)
        outlineOverlay.frame = bounds
        outlineOverlay.canvasFrame = canvasFrame
        outlineOverlay.sourceFrames = geometry.activeLayerOrder
            .filter { hasLiveContent(for: $0) }
            .map { frame(for: $0) }
    }

    func hasLiveContent(for layer: SceneLayerKind) -> Bool {
        switch layer {
        case .screen:
            return screenPreview.hasPreviewContent
        case .camera:
            return cameraPreview.hasPreviewContent
        }
    }

    func frame(for layer: SceneLayerKind) -> NSRect {
        switch layer {
        case .screen:
            return screenPreview.frame
        case .camera:
            return cameraPreview.frame
        }
    }

    func canEditLayerFrame(_ layer: SceneLayerKind) -> Bool {
        PreviewStageEditing.canEditLayerFrame(
            layer,
            allowsLayerInteraction: allowsLayerInteraction,
            enabledSources: enabledSources,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled,
            isScreenCropEditingEnabled: isScreenCropEditingEnabled
        )
    }

    func canBeginScreenCropPan(_ layer: SceneLayerKind) -> Bool {
        allowsLayerInteraction
            && layer == .screen
            && enabledSources.contains(.screen)
            && screenContentMode == .fill
            && !isCameraCropEditingEnabled
            && !isScreenCropEditingEnabled
    }

    func normalizedFrame(for layer: SceneLayerKind) -> CGRect {
        sceneLayout.frame(for: layer)
    }

    func normalizedSelectionFrame(for layer: SceneLayerKind) -> CGRect {
        normalized(selectionFrame(for: layer), in: canvasFrame)
    }

    func projectedFrame(for layer: SceneLayerKind, in canvas: NSRect) -> NSRect {
        let geometry = renderGeometry(in: canvas)
        if layer == .screen,
           screenContentMode == .fit,
           !isScreenCropEditingEnabled {
            return geometry.sourceFrame(
                for: .screen,
                sourceAspectRatio: effectiveScreenSourceAspectRatio
            )
        }
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

    func renderGeometry(in canvas: NSRect) -> SceneRenderGeometry {
        let request = PreviewStageLayout.RenderRequest(
            canvas: canvas,
            enabledSources: enabledSources,
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
        if let cachedRenderGeometry, cachedRenderGeometry.request == request {
            return cachedRenderGeometry.value
        }
        let value = PreviewStageLayout.geometry(request)
        cachedRenderGeometry = (request, value)
        cachedCameraCropGeometry = nil
        cachedScreenCropSourceFrame = nil
        cachedCameraFillFlags = nil
        return value
    }

    var cameraFillFlags: (fullscreen: Bool, fullWidth: Bool) {
        if let cachedCameraFillFlags { return cachedCameraFillFlags }
        let geometry = renderGeometry(in: canvasFrame)
        let flags = (
            fullscreen: geometry.isFullCanvasFrame(for: .camera),
            fullWidth: geometry.isFullCanvasWidth(for: .camera)
        )
        cachedCameraFillFlags = flags
        return flags
    }

    var isFullscreenCameraPreview: Bool {
        cameraFillFlags.fullscreen
    }

    var effectiveScreenSourceAspectRatio: CGFloat {
        screenSourceAspectRatio
    }

    var isFullWidthCameraPreview: Bool {
        cameraFillFlags.fullWidth
    }

    func normalized(_ frame: NSRect, in canvas: NSRect) -> CGRect {
        CGRect(
            x: (frame.minX - canvas.minX) / max(1, canvas.width),
            y: (frame.minY - canvas.minY) / max(1, canvas.height),
            width: frame.width / max(1, canvas.width),
            height: frame.height / max(1, canvas.height)
        )
    }

    func refreshCanvasBackground() {
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 2
        canvasBackgroundLayer.contentsScale = scale
        let width = Int((canvasBackgroundLayer.bounds.width * scale).rounded(.up))
        let height = Int((canvasBackgroundLayer.bounds.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return }
        let key = BackgroundRenderKey(style: canvasBackgroundStyle, width: width, height: height)
        if renderedBackgroundKey == key {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let appearance = canvasBackgroundStyle.appearance
        canvasBackgroundLayer.backgroundColor = appearance.solidCGColor
        CATransaction.commit()
        guard requestedBackgroundKey != key else { return }
        requestedBackgroundKey = key
        backgroundRenderTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderCanvasBackground(key)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        backgroundRenderTimer = timer
    }

    func renderCanvasBackground(_ key: BackgroundRenderKey) {
        guard requestedBackgroundKey == key,
              !canvasBackgroundAnimated || !canvasBackgroundStyle.supportsBackgroundAnimation else { return }
        backgroundRenderTimer = nil
        backgroundAnimationQueue.async {
            let image = key.style.appearance.renderCGImage(pixelWidth: key.width, pixelHeight: key.height)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestedBackgroundKey == key else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.canvasBackgroundLayer.contents = image
                CATransaction.commit()
                self.renderedBackgroundKey = key
                self.requestedBackgroundKey = nil
            }
        }
    }

    func invalidateCanvasBackgroundRender() {
        backgroundRenderTimer?.invalidate()
        backgroundRenderTimer = nil
        requestedBackgroundKey = nil
        renderedBackgroundKey = nil
    }


    func updateBackgroundAnimation() {
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

    func renderAnimatedBackgroundFrame() {
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

    func updateCanvasSelectionAffordance() {
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

    func applyLayerOrder() {
        let order = sceneLayout.layerOrder
        if lastLayerOrder == order {
            return
        }
        lastLayerOrder = order
        for (index, kind) in order.enumerated() {
            let zPosition = CGFloat(index)
            switch kind {
            case .screen:
                screenPreview.layer?.zPosition = zPosition
            case .camera:
                cameraPreview.layer?.zPosition = zPosition
                cameraShadowLayer.zPosition = zPosition - 0.5
            }
        }
        safeZoneOverlay.layer?.zPosition = CGFloat(order.count + 1)
        selectionOverlay.layer?.zPosition = CGFloat(order.count + 2)
    }

    func updateSafeZoneOverlayVisibility() {
        let showsSocialSafeZone = captureLayout == .vertical && socialSafeZoneOverlay != .none
        safeZoneOverlay.isHidden = !showsRuleOfThirdsOverlay && !showsSocialSafeZone
    }

    func updateSelectionOverlay() {
        let key = SelectionOverlayKey(
            isBackgroundLayerSelected: isBackgroundLayerSelected,
            isScreenCropEditingEnabled: isScreenCropEditingEnabled,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled,
            selectedLayer: selectedLayer,
            canvasFrame: canvasFrame,
            bounds: bounds,
            enabledSources: enabledSources,
            allowsLayerInteraction: allowsLayerInteraction,
            allowsCameraCropInteraction: allowsCameraCropInteraction,
            sceneLayout: sceneLayout,
            screenCrop: screenCropDraft ?? screenCrop,
            cameraCropAmount: activeCameraCropAmount,
            cameraCropPosition: activeCameraCropPosition,
            cameraFramePadding: cameraFramePadding,
            cameraContentMode: cameraContentMode,
            screenContentMode: screenContentMode,
            cameraSourceAspectRatio: cameraPreview.currentSourceAspectRatio,
            screenSourceAspectRatio: effectiveScreenSourceAspectRatio,
            screenFillsSceneFrame: screenFillsSceneFrame
        )
        if lastSelectionOverlayKey == key {
            return
        }
        lastSelectionOverlayKey = key

        let mode = PreviewStageSelection.mode(.init(
            isBackgroundLayerSelected: isBackgroundLayerSelected,
            isScreenCropEditingEnabled: isScreenCropEditingEnabled,
            hasScreen: enabledSources.contains(.screen),
            canvasIsEmpty: canvasFrame.isEmpty,
            allowsLayerInteraction: allowsLayerInteraction,
            allowsCameraCropInteraction: allowsCameraCropInteraction,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled,
            selectedLayer: selectedLayer,
            hasSelectedSource: enabledSources.contains(selectedLayer.source)
        ))
        let appearance = PreviewStageSelection.appearance(.init(
            mode: mode,
            bounds: bounds,
            canvasFrame: canvasFrame,
            screenSourceFrame: mode == .screenCrop ? screenCropSourceFrame() : .zero,
            screenCropFrame: mode == .screenCrop ? screenCropFrame() : .zero,
            cameraSourceFrame: mode == .cameraCrop ? cameraCropSourceFrame() : .zero,
            cameraCropFrame: mode == .cameraCrop ? cameraCropFrame() : .zero,
            layerFrame: mode == .layer ? interactiveFrame(for: selectedLayer) : .zero,
            showsLayerResizeHandles: mode == .layer && canEditLayerFrame(selectedLayer)
        ))
        selectionOverlay.apply(appearance)
        cropToolbarFrame = appearance.cropToolbarFrame
    }

    func cameraCropDragMode(at point: CGPoint) -> DragMode.Kind? {
        PreviewStageEditing.cameraCropDragMode(
            at: point,
            cropFrame: cameraCropFrame(),
            allowsCameraCropInteraction: allowsCameraCropInteraction
        )
    }

    func screenCropDragMode(at point: CGPoint) -> DragMode.Kind? {
        PreviewStageEditing.screenCropDragMode(
            at: point,
            cropFrame: screenCropFrame(),
            constrainedTo: screenCropSourceFrame()
        )
    }

    func interactiveFrame(for layer: SceneLayerKind) -> NSRect {
        let sourceFrame = frame(for: layer)
        guard !canvasFrame.isEmpty else { return sourceFrame }
        let visibleFrame = sourceFrame.intersection(canvasFrame)
        return visibleFrame.isEmpty ? sourceFrame : visibleFrame
    }

    func selectionFrame(for layer: SceneLayerKind) -> NSRect {
        frame(for: layer)
    }

    func updateCameraCrop(movingFrom dragMode: DragMode, to location: CGPoint) {
        let cropGeometry = cameraCropGeometry()
        guard cropGeometry.sourceFrame.width > 0, cropGeometry.sourceFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        applyCameraCropControl(
            for: cropGeometry.movedCropFrame(
                startCrop,
                delta: PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location)
            ),
            using: cropGeometry
        )
    }

    func updateCameraCrop(resizingFrom dragMode: DragMode, anchor: ResizeAnchor, to location: CGPoint) {
        let cropGeometry = cameraCropGeometry()
        guard cropGeometry.sourceFrame.width > 0, cropGeometry.sourceFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        applyCameraCropControl(
            for: cropGeometry.resizedCropFrame(
                startCrop,
                delta: PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location),
                anchor: anchor
            ),
            using: cropGeometry
        )
    }

    func applyCameraCropControl(for crop: CGRect, using cropGeometry: CameraCropGeometry) {
        guard let control = cropGeometry.control(for: crop) else { return }
        updateCameraCropDraft(amount: control.amount, position: control.position)
    }

    func updateScreenCrop(movingFrom dragMode: DragMode, to location: CGPoint) {
        let sourceFrame = screenCropSourceFrame()
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
        let delta = PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location)
        let moved = dragMode.startFrame.offsetBy(dx: delta.x, dy: delta.y)
        updateScreenCropDraft(screenCropFrame: PreviewStageCropGeometry.clampedPixelFrame(moved, in: sourceFrame))
    }

    func updateScreenCrop(resizingFrom dragMode: DragMode, anchor: ResizeAnchor, to location: CGPoint) {
        let sourceFrame = screenCropSourceFrame()
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
        let delta = PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location)
        updateScreenCropDraft(
            screenCropFrame: PreviewStageCropGeometry.resizedPixelFrame(
                dragMode.startFrame,
                delta: delta,
                anchor: anchor,
                in: sourceFrame
            )
        )
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
        guard let crop = PreviewStageCropSession.committedCameraCrop(
            isEditing: isCameraCropEditingEnabled,
            amount: activeCameraCropAmount,
            position: activeCameraCropPosition
        ) else { return }
        isCameraCropEditingEnabled = false
        cameraCropDraftAmount = nil
        cameraCropDraftPosition = nil
        cameraCropAmount = crop.0
        cameraCropPosition = crop.1
        onCameraCropChanged?(crop.0, crop.1)
    }

    func cancelCameraCropEditing() {
        cameraCropDraftAmount = nil
        cameraCropDraftPosition = nil
        isCameraCropEditingEnabled = false
    }

    func commitScreenCropEditing() {
        guard let draft = PreviewStageCropSession.committedScreenCrop(
            isEditing: isScreenCropEditingEnabled,
            draft: screenCropDraft
        ) else { return }
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

    var activeCameraCropAmount: CGPoint {
        cameraCropDraftAmount ?? cameraCropAmount
    }

    var activeCameraCropPosition: CGPoint {
        cameraCropDraftPosition ?? cameraCropPosition
    }

    func syncPreviewCrop() {
        let amount = isCameraCropEditingEnabled ? .zero : cameraCropAmount
        let position = isCameraCropEditingEnabled ? .zero : cameraCropPosition
        guard cameraPreview.sourceCropAmount != amount || cameraPreview.sourceCropPosition != position else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cameraPreview.sourceCropAmount = amount
        cameraPreview.sourceCropPosition = position
        CATransaction.commit()
    }

    func cameraCropFrame() -> CGRect {
        cameraCropFrame(amount: activeCameraCropAmount, position: activeCameraCropPosition)
    }

    func cameraCropFrame(amount: CGPoint, position: CGPoint) -> CGRect {
        cameraCropGeometry().cropFrame(amount: amount, position: position)
    }

    func cameraCropSourceFrame() -> CGRect {
        cameraCropGeometry().sourceFrame
    }

    func cameraCropGeometry() -> CameraCropGeometry {
        let render = renderGeometry(in: canvasFrame)
        let aspect = cameraPreview.currentSourceAspectRatio
        if let cachedRenderGeometry,
           let cachedCameraCropGeometry,
           cachedCameraCropGeometry.request == cachedRenderGeometry.request,
           cachedCameraCropGeometry.aspect == aspect {
            return cachedCameraCropGeometry.value
        }
        let value = CameraCropGeometry(
            renderGeometry: render,
            sourceAspectRatio: aspect
        )
        if let cachedRenderGeometry {
            cachedCameraCropGeometry = (cachedRenderGeometry.request, aspect, value)
        }
        return value
    }

    func screenCropSourceFrame() -> CGRect {
        let aspect = screenSourceAspectRatio
        if let cachedRenderGeometry,
           let cachedScreenCropSourceFrame,
           cachedScreenCropSourceFrame.request == cachedRenderGeometry.request,
           cachedScreenCropSourceFrame.aspect == aspect {
            return cachedScreenCropSourceFrame.value
        }
        let value = PreviewStageCropGeometry.fittedSourceFrame(
            target: projectedFrame(for: .screen, in: canvasFrame),
            sourceAspectRatio: aspect
        )
        if let cachedRenderGeometry {
            cachedScreenCropSourceFrame = (cachedRenderGeometry.request, aspect, value)
        }
        return value
    }

    func screenCropFrame() -> CGRect {
        PreviewStageCropGeometry.cropFrame(
            in: screenCropSourceFrame(),
            normalizedCrop: screenCropDraft ?? screenCrop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        )
    }

    func defaultScreenCropDraft() -> CGRect {
        PreviewStageCropGeometry.defaultDraft(
            sourceFrame: screenCropSourceFrame(),
            targetFrame: projectedFrame(for: .screen, in: canvasFrame)
        )
    }

    func updateScreenCropDraft(screenCropFrame: CGRect) {
        screenCropDraft = PreviewStageCropGeometry.normalizedCrop(
            pixelFrame: screenCropFrame,
            in: screenCropSourceFrame()
        )
        updateSelectionOverlay()
        invalidateResizeCursorRects()
    }
}
