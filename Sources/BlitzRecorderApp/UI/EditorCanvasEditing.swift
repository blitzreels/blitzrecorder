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
    /// The background only shows through spacing, a fitted source, or a layout that leaves part of the canvas empty.
    static func showsBackground(_ scene: RecordingScene) -> Bool {
        if scene.canvasPadding > 0.001 { return true }
        if scene.renderedSources.contains(.screen), scene.screenCornerRadius > 0.001 { return true }
        let sources = scene.renderedSources
        if sources.contains(.screen), scene.screenContentMode == .fit { return true }
        if sources.contains(.camera), scene.cameraContentMode == .fit { return true }
        let canvas = CGRect(x: 0, y: 0, width: 1, height: 1)
        let frames = [CaptureSource.screen, .camera].filter(sources.contains).map {
            ($0 == .screen ? scene.sceneLayout.screenFrame : scene.sceneLayout.cameraFrame).intersection(canvas)
        }
        if frames.contains(where: { $0.width > 0.999 && $0.height > 0.999 }) { return false }
        let area: (CGRect) -> CGFloat = { $0.isNull ? 0 : $0.width * $0.height }
        let overlap = frames.count == 2 ? area(frames[0].intersection(frames[1])) : 0
        return frames.reduce(0) { $0 + area($1) } - overlap < 0.995
    }

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
                    .stroke(BlitzUI.accent, lineWidth: 1.5)
            } else if isHovering {
                Rectangle()
                    .stroke(BlitzUI.accent.opacity(0.82), lineWidth: 1.25)
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
                    .font(BlitzType.footnote.monospaced())
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
            .fill(BlitzUI.accent)
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
            .fill(BlitzUI.accent)
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
                    .fill(BlitzUI.accent)
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
