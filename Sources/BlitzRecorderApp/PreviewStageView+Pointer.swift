import AppKit

extension PreviewStageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !canvasFrame.isEmpty else { return }

        if isScreenCropEditingEnabled, enabledSources.contains(.screen) {
            addCropCursorRects(frame: screenCropFrame(), sourceFrame: screenCropSourceFrame())
            return
        }

        if allowsCameraCropInteraction, isCameraCropEditingEnabled, enabledSources.contains(.camera) {
            addCropCursorRects(frame: frame(for: .camera), sourceFrame: cameraCropSourceFrame())
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
            for (anchor, rect) in PreviewStageEditing.resizeTargets(for: selectionFrame(for: layer)) {
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

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hit = interactionHit(at: location)
        let layer: SceneLayerKind?
        switch hit {
        case .resize(let kind, _), .layer(let kind):
            layer = kind
        default:
            layer = nil
        }
        switch PreviewStageDrag.begin(.init(
            hit: hit,
            location: location,
            selectedLayer: selectedLayer,
            canEditLayer: layer.map(canEditLayerFrame) ?? false,
            canBeginScreenCropPan: layer.map(canBeginScreenCropPan) ?? false,
            screenCropFrame: screenCropFrame(),
            cameraNormalizedFrame: normalizedFrame(for: .camera),
            layerSelectionFrame: layer.map(selectionFrame(for:)) ?? .zero,
            layerNormalizedSelection: layer.map(normalizedSelectionFrame(for:)) ?? .zero,
            layerNormalizedFrame: layer.map(normalizedFrame(for:)) ?? .zero,
            cameraCropAmount: cameraCropAmount,
            cameraCropPosition: cameraCropPosition,
            activeCameraCropAmount: activeCameraCropAmount,
            activeCameraCropPosition: activeCameraCropPosition
        )) {
        case .ignore:
            dragMode = nil
            return
        case .background:
            isBackgroundLayerSelected = true
            onBackgroundSelected?()
            dragMode = nil
        case .select(let selected, let drag, let cursor):
            if case .layer = hit {
                isBackgroundLayerSelected = false
            }
            selectedLayer = selected
            onLayerSelected?(selected)
            dragMode = drag
            PreviewStageDrag.apply(cursor)
            if drag == nil {
                needsDisplay = true
                return
            }
        }
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
        guard PreviewStageDrag.allowsInteraction(
            kind: dragMode.kind,
            isScreenCropEditingEnabled: isScreenCropEditingEnabled,
            allowsCameraCropInteraction: allowsCameraCropInteraction,
            allowsLayerInteraction: allowsLayerInteraction
        ) else {
            self.dragMode = nil
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let delta = PreviewStageDrag.canvasDelta(
            from: dragMode.startPoint,
            to: location,
            canvasSize: canvasFrame.size
        )
        if lastDragCursorKind != dragMode.kind {
            lastDragCursorKind = dragMode.kind
            PreviewStageDrag.dragCursor(for: dragMode.kind).set()
        }
        guard delta.x != 0 || delta.y != 0 else { return }
        switch PreviewStageDrag.tick(.init(
            kind: dragMode.kind,
            layer: dragMode.layer,
            startFrame: dragMode.startFrame,
            delta: delta,
            screenContentMode: screenContentMode
        )) {
        case .layerFrame(let frame):
            applyLayerDragFrame(frame, layer: dragMode.layer)
        case .beginScreenCropPan(let frame):
            onScreenCropPanRequested?()
            if isScreenCropEditingEnabled {
                let cropDragMode = DragMode(
                    kind: .screenCropMove,
                    layer: .screen,
                    startPoint: dragMode.startPoint,
                    startFrame: screenCropFrame(),
                    startCropAmount: cameraCropAmount,
                    startCropPosition: cameraCropPosition
                )
                self.dragMode = cropDragMode
                updateScreenCrop(movingFrom: cropDragMode, to: location)
                return
            }
            applyLayerDragFrame(frame, layer: dragMode.layer)
        case .cameraCropMove:
            updateCameraCrop(movingFrom: dragMode, to: location)
        case .cameraCropResize(let anchor):
            updateCameraCrop(resizingFrom: dragMode, anchor: anchor, to: location)
        case .screenCropMove:
            updateScreenCrop(movingFrom: dragMode, to: location)
        case .screenCropResize(let anchor):
            updateScreenCrop(resizingFrom: dragMode, anchor: anchor, to: location)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let completedDragMode = dragMode
        let resizedLayer: SceneLayerKind?
        if case .resize = completedDragMode?.kind {
            resizedLayer = completedDragMode?.layer
        } else {
            resizedLayer = nil
        }
        dragMode = nil
        invalidateResizeCursorRects()
        if let completedDragMode {
            switch completedDragMode.kind {
            case .move, .resize:
                onSceneLayoutEditingEnded?(sceneLayout)
            case .cropMove, .cropResize, .screenCropMove, .screenCropResize:
                break
            }
        }
        if let resizedLayer {
            onLayerResizeEnded?(resizedLayer)
        }
    }

    func layer(at point: CGPoint) -> SceneLayerKind? {
        PreviewStageEditing.layer(
            at: point,
            sceneLayout: sceneLayout,
            enabledSources: enabledSources,
            frameForLayer: frame(for:)
        )
    }

    func resizeHit(at point: CGPoint) -> (SceneLayerKind, ResizeAnchor)? {
        guard canEditLayerFrame(selectedLayer),
              let anchor = PreviewStageEditing.resizeAnchor(at: point, in: selectionFrame(for: selectedLayer)) else {
            return nil
        }
        return (selectedLayer, anchor)
    }

    func cursor(at point: CGPoint) -> NSCursor {
        switch interactionHit(at: point) {
        case .screenCrop(let mode), .cameraCrop(let mode):
            return PreviewStageCursors.cursor(for: mode)
        case .resize(_, let anchor):
            return anchor.cursor
        case .layer(let layer):
            return canEditLayerFrame(layer) || canBeginScreenCropPan(layer) ? .openHand : .arrow
        case .background, .ignore:
            return .arrow
        }
    }

    private func addCropCursorRects(frame: CGRect, sourceFrame: CGRect) {
        let moveRect = frame.insetBy(dx: 12, dy: 12)
        if moveRect.width > 0, moveRect.height > 0 {
            addCursorRect(moveRect, cursor: .openHand)
        }
        for (anchor, rect) in PreviewStageEditing.resizeTargets(for: frame, constrainedTo: sourceFrame) {
            addCursorRect(rect, cursor: anchor.cursor)
        }
    }
}
