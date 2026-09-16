import AppKit
import SwiftUI

struct EditorLayoutDraft {
    let eventIndex: Int
    let startLayout: SceneLayout
    let startCameraContentMode: CameraContentMode
    var scene: RecordingScene

    var hasLayoutChanges: Bool {
        scene.sceneLayout != startLayout || scene.cameraContentMode != startCameraContentMode
    }

    mutating func applyMove(kind: SceneLayerKind, translation: CGSize) {
        var frame = startLayout.frame(for: kind)
        frame.origin.x += translation.width
        frame.origin.y -= translation.height
        scene.sceneLayout.setFrame(SceneLayerResizing.clamped(frame), for: kind)
    }

    mutating func applyResize(
        kind: SceneLayerKind,
        anchor: ResizeAnchor,
        translation: CGSize,
        aspectLocked: Bool,
        visibleStartFrame: CGRect?
    ) {
        let start = resizeStartFrame(kind: kind, visibleFrame: visibleStartFrame)
        let resized = SceneLayerResizing.resized(
            start,
            delta: CGPoint(x: translation.width, y: -translation.height),
            anchor: anchor,
            aspectRatio: aspectLocked && start.height > 0 ? start.width / start.height : nil
        )
        if kind == .camera, !aspectLocked || !anchor.keepsAspectRatio {
            scene.cameraContentMode = .fill
        }
        scene.sceneLayout.setFrame(resized, for: kind)
    }

    func resizeStartFrame(kind: SceneLayerKind, visibleFrame: CGRect?) -> CGRect {
        guard kind == .camera, scene.cameraContentMode == .fit, let visibleFrame else {
            return startLayout.frame(for: kind)
        }
        return CGRect(
            x: visibleFrame.minX,
            y: 1 - visibleFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }
}

enum EditorCanvasAppearance {
    static func copy(_ draft: RecordingScene, into scene: inout RecordingScene) {
        scene.canvasBackgroundStyle = draft.canvasBackgroundStyle
        scene.canvasPadding = draft.canvasPadding
        scene.screenCornerRadius = draft.screenCornerRadius
        scene.screenShadowEnabled = draft.screenShadowEnabled
    }

    static func clampedPadding(_ padding: CGFloat) -> CGFloat {
        min(0.12, max(0, padding))
    }

    static func clampedCornerRadius(_ radius: CGFloat) -> CGFloat {
        min(0.12, max(0, radius))
    }
}

enum EditorCanvasLayers {
    static func make(
        frames: [(kind: SceneLayerKind, frame: CGRect)],
        canvasAspectRatio: CGFloat,
        lockedKinds: Set<SceneLayerKind>,
        selection: EditorSelection?,
        isEditable: Bool,
        assetID: (SceneLayerKind) -> String?
    ) -> [EditorCanvasLayer] {
        frames.map { kind, frame in
            let id = assetID(kind)
            return EditorCanvasLayer(
                kind: kind,
                assetID: id,
                frame: frame,
                displayAspectRatio: frame.height > 0 ? frame.width / frame.height * canvasAspectRatio : 1,
                isAspectRatioLocked: lockedKinds.contains(kind),
                isSelected: id.map { selection == .asset($0) } ?? false,
                isEditable: isEditable
            )
        }
    }
}

enum EditorCanvasSession {
    static func canEditLayout(_ scene: RecordingScene, isPlaybackReady: Bool) -> Bool {
        isPlaybackReady && !scene.enabledSources.intersection([.screen, .camera]).isEmpty
    }

    static func ensureDraft(
        existing: EditorLayoutDraft?,
        eventIndex: Int,
        events: [RecordingSceneEvent],
        currentTime: Double,
        duration: Double,
        isPlaybackReady: Bool
    ) -> (draft: EditorLayoutDraft, seekTime: Double?)? {
        if let existing {
            return (existing, nil)
        }
        guard events.indices.contains(eventIndex) else { return nil }
        let event = events[eventIndex]
        guard canEditLayout(event.scene, isPlaybackReady: isPlaybackReady) else { return nil }
        let transitionEnd = event.time + event.transition.duration
        let seekTime = currentTime < transitionEnd ? min(transitionEnd, duration) : nil
        return (
            EditorLayoutDraft(
                eventIndex: eventIndex,
                startLayout: event.scene.sceneLayout,
                startCameraContentMode: event.scene.cameraContentMode,
                scene: event.scene
            ),
            seekTime
        )
    }

    enum Commit: Equatable {
        case discard
        case apply
        case revertUnchanged
        case failed
    }

    static func commit(hasChanges: Bool, succeeded: Bool, projectChanged: Bool) -> Commit {
        guard hasChanges else { return .discard }
        guard succeeded else { return .failed }
        return projectChanged ? .apply : .revertUnchanged
    }
}

struct EditorCanvasLayer: Identifiable {
    let kind: SceneLayerKind
    let assetID: String?
    let frame: CGRect      // normalized 0...1, top-left origin
    let displayAspectRatio: CGFloat
    let isAspectRatioLocked: Bool
    let isSelected: Bool
    let isEditable: Bool

    var id: String { kind.rawValue }
}

private let editorCanvasSpace = "EditorCanvasOverlay"

struct EditorCanvasLayerOverlay: View {
    let layers: [EditorCanvasLayer]
    let onSelect: (EditorCanvasLayer) -> Void
    let onMove: (SceneLayerKind, CGSize, Bool) -> Void
    let onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void
    @State private var hoveredLayerID: String?

    var body: some View {
        GeometryReader { proxy in
            ForEach(layers) { layer in
                EditorCanvasLayerView(
                    layer: layer,
                    isHovering: hoveredLayerID == layer.id
                )
                .frame(
                    width: layer.frame.width * proxy.size.width,
                    height: layer.frame.height * proxy.size.height
                )
                .offset(
                    x: layer.frame.minX * proxy.size.width,
                    y: layer.frame.minY * proxy.size.height
                )
                .allowsHitTesting(false)
            }

            EditorCanvasInteractionView(
                layers: layers,
                hoveredLayerID: $hoveredLayerID,
                onSelect: onSelect,
                onMove: { kind, translation, ended in
                    onMove(kind, normalized(translation, in: proxy.size), ended)
                },
                onResize: { kind, anchor, translation, ended in
                    onResize(kind, anchor, normalized(translation, in: proxy.size), ended)
                }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .coordinateSpace(name: editorCanvasSpace)
    }

    private func normalized(_ translation: CGSize, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGSize(width: translation.width / size.width, height: translation.height / size.height)
    }
}

struct EditorCanvasLayerView: View {
    let layer: EditorCanvasLayer
    let isHovering: Bool

    var body: some View {
        ZStack {
            if layer.isSelected {
                Rectangle()
                    .stroke(BlitzUI.mint, lineWidth: 1.5)
            } else if isHovering {
                Rectangle()
                    .stroke(BlitzUI.mint.opacity(0.82), lineWidth: 1.25)
            }
        }
        .overlay {
            if layer.isSelected && layer.isEditable {
                resizeHandles
            }
        }
        .overlay(alignment: .top) {
            if layer.isSelected && layer.isEditable {
                Label(
                    EditorFrameRatioLabel.text(for: layer.displayAspectRatio),
                    systemImage: layer.isAspectRatioLocked ? "lock.fill" : "lock.open.fill"
                )
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.black.opacity(0.78), in: .capsule)
                    .padding(.top, 8)
            }
        }
    }

    private var resizeHandles: some View {
        ZStack {
            handle(.topLeft, alignment: .topLeading)
            handle(.topRight, alignment: .topTrailing)
            handle(.bottomLeft, alignment: .bottomLeading)
            handle(.bottomRight, alignment: .bottomTrailing)
            horizontalEdgeHandle(alignment: .top)
            horizontalEdgeHandle(alignment: .bottom)
            verticalEdgeHandle(alignment: .leading)
            verticalEdgeHandle(alignment: .trailing)
        }
    }

    private func horizontalEdgeHandle(alignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(BlitzUI.mint)
            .frame(width: 24, height: 6)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.black.opacity(0.9), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(y: alignment.vertical == .top ? -3 : 3)
    }

    private func verticalEdgeHandle(alignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(BlitzUI.mint)
            .frame(width: 6, height: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.black.opacity(0.9), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(x: alignment.horizontal == .leading ? -3 : 3)
    }

    private func handle(_ anchor: ResizeAnchor, alignment: Alignment) -> some View {
        let offsetX: CGFloat = alignment.horizontal == .leading ? -6 : 6
        let offsetY: CGFloat = alignment.vertical == .top ? -6 : 6
        return Rectangle()
            .fill(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: alignment) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(BlitzUI.mint)
                    .frame(width: 12, height: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.9), lineWidth: 1)
                    }
                    .padding(2)
                    .offset(x: offsetX, y: offsetY)
            }
    }
}

struct EditorCanvasInteractionView: NSViewRepresentable {
    let layers: [EditorCanvasLayer]
    @Binding var hoveredLayerID: String?
    let onSelect: (EditorCanvasLayer) -> Void
    let onMove: (SceneLayerKind, CGSize, Bool) -> Void
    let onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.layers = layers
        view.hoveredLayerID = hoveredLayerID
        view.onHover = { hoveredLayerID = $0 }
        view.onSelect = onSelect
        view.onMove = onMove
        view.onResize = onResize
        view.needsDisplay = true
    }

    final class InteractionView: NSView {
        enum DragMode {
            case move(SceneLayerKind)
            case resize(SceneLayerKind, ResizeAnchor)
        }

        var layers: [EditorCanvasLayer] = []
        var hoveredLayerID: String?
        var onHover: ((String?) -> Void)?
        var onSelect: ((EditorCanvasLayer) -> Void)?
        var onMove: ((SceneLayerKind, CGSize, Bool) -> Void)?
        var onResize: ((SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragMode: DragMode?
        private var dragStart: CGPoint = .zero

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
            trackingArea = area
            addTrackingArea(area)
        }

        override func mouseMoved(with event: NSEvent) {
            guard dragMode == nil else { return }
            let point = convert(event.locationInWindow, from: nil)
            setHoveredLayer(resizeHit(at: point)?.layer.id ?? hitLayer(at: point)?.id)
            cursor(at: point).set()
        }

        override func mouseExited(with event: NSEvent) {
            guard dragMode == nil else { return }
            setHoveredLayer(nil)
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            dragStart = point
            if let hit = resizeHit(at: point) {
                onSelect?(hit.layer)
                setHoveredLayer(hit.layer.id)
                dragMode = .resize(hit.layer.kind, hit.anchor)
                hit.anchor.cursor.set()
                return
            }
            guard let layer = hitLayer(at: point) else {
                dragMode = nil
                setHoveredLayer(nil)
                return
            }
            onSelect?(layer)
            setHoveredLayer(layer.id)
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                dragMode = .resize(layer.kind, anchor)
                anchor.cursor.set()
            } else if layer.isEditable {
                dragMode = .move(layer.kind)
                NSCursor.closedHand.set()
            } else {
                dragMode = nil
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragMode else { return }
            let point = convert(event.locationInWindow, from: nil)
            let translation = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            switch dragMode {
            case .move(let kind):
                onMove?(kind, translation, false)
            case .resize(let kind, let anchor):
                onResize?(kind, anchor, translation, false)
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let dragMode else { return }
            let point = convert(event.locationInWindow, from: nil)
            let translation = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            switch dragMode {
            case .move(let kind):
                onMove?(kind, translation, true)
            case .resize(let kind, let anchor):
                onResize?(kind, anchor, translation, true)
            }
            self.dragMode = nil
            cursor(at: point).set()
        }

        private func hitLayer(at point: CGPoint) -> EditorCanvasLayer? {
            layers.reversed().first { frame(for: $0).contains(point) }
        }

        private func resizeHit(at point: CGPoint) -> (layer: EditorCanvasLayer, anchor: ResizeAnchor)? {
            for layer in layers.reversed() where layer.isSelected && layer.isEditable {
                if let anchor = resizeAnchor(at: point, in: layer) {
                    return (layer, anchor)
                }
            }
            return nil
        }

        private func frame(for layer: EditorCanvasLayer) -> CGRect {
            CGRect(
                x: layer.frame.minX * bounds.width,
                y: layer.frame.minY * bounds.height,
                width: layer.frame.width * bounds.width,
                height: layer.frame.height * bounds.height
            )
        }

        private func resizeAnchor(at point: CGPoint, in layer: EditorCanvasLayer) -> ResizeAnchor? {
            let frame = frame(for: layer)
            let size: CGFloat = 18
            let half = size / 2
            let cornerHandles: [(ResizeAnchor, CGRect)] = [
                (.topLeft, CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size)),
                (.topRight, CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)),
                (.bottomLeft, CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size)),
                (.bottomRight, CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size))
            ]
            if let corner = cornerHandles.first(where: { $0.1.contains(point) }) {
                return corner.0
            }

            let edgeThickness: CGFloat = 16
            let edgeHalf = edgeThickness / 2
            let edgeHandles: [(ResizeAnchor, CGRect)] = [
                (.top, CGRect(
                    x: frame.minX + half,
                    y: frame.minY - edgeHalf,
                    width: max(0, frame.width - size),
                    height: edgeThickness
                )),
                (.right, CGRect(
                    x: frame.maxX - edgeHalf,
                    y: frame.minY + half,
                    width: edgeThickness,
                    height: max(0, frame.height - size)
                )),
                (.bottom, CGRect(
                    x: frame.minX + half,
                    y: frame.maxY - edgeHalf,
                    width: max(0, frame.width - size),
                    height: edgeThickness
                )),
                (.left, CGRect(
                    x: frame.minX - edgeHalf,
                    y: frame.minY + half,
                    width: edgeThickness,
                    height: max(0, frame.height - size)
                ))
            ]
            return edgeHandles.first { $0.1.contains(point) }?.0
        }

        private func cursor(at point: CGPoint) -> NSCursor {
            if let hit = resizeHit(at: point) {
                return hit.anchor.cursor
            }
            guard let layer = hitLayer(at: point) else { return .arrow }
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                return anchor.cursor
            }
            return layer.isEditable ? .openHand : .pointingHand
        }

        private func setHoveredLayer(_ id: String?) {
            guard hoveredLayerID != id else { return }
            hoveredLayerID = id
            onHover?(id)
        }
    }
}
