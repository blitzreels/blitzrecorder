import AppKit

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
}
