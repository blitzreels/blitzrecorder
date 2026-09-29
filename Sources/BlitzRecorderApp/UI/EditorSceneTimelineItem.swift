import SwiftUI

struct EditorSceneTimelineItem: View {
    let scene: RecordingScene
    let canvasAspectRatio: CGFloat
    let isSelected: Bool
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private let shape = RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)

    var body: some View {
        GeometryReader { proxy in
            let presentation = EditorSceneTimelineItemPresentation.make(scene: scene)
            HStack(spacing: 6) {
                EditorSceneTimelineThumbnail(scene: scene, canvasAspectRatio: canvasAspectRatio)
                    .frame(width: thumbnailWidth(for: proxy.size.width), height: 26)

                if proxy.size.width >= 86 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                            .font(BlitzType.captionEmphasis)
                            .foregroundStyle(BlitzUI.primaryText)
                            .lineLimit(1)

                        if let detail = presentation.detail {
                            Text(detail)
                                .font(BlitzType.footnote)
                                .foregroundStyle(BlitzUI.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(isHovering ? BlitzUI.hoverFill : isActive ? BlitzUI.trackCamera.opacity(0.12) : BlitzUI.cardFill, in: shape)
        .overlay {
            shape.strokeBorder(
                isSelected || isHovering ? BlitzUI.mint : (isActive ? BlitzUI.panelStroke : BlitzUI.separator),
                lineWidth: isSelected || isHovering ? 2 : 1
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(BlitzUI.mint)
                    .frame(width: 3)
                    .padding(.vertical, 5)
                    .padding(.leading, 2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .onHover { isHovering = $0 && isEnabled }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EditorSceneTimelineItemPresentation.make(scene: scene).title)
    }

    private func thumbnailWidth(for itemWidth: CGFloat) -> CGFloat {
        if itemWidth >= 86 {
            return min(52, max(24, itemWidth * 0.36))
        }
        return max(6, itemWidth - 8)
    }
}

private struct EditorSceneTimelineThumbnail: View {
    let scene: RecordingScene
    let canvasAspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let canvas = fittedCanvas(in: proxy.size)
            let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(cgColor: scene.canvasBackgroundStyle.appearance.solidCGColor))
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: canvas.minX, y: canvas.minY)

                ForEach(geometry.activePlacements, id: \.kind) { placement in
                    sourceLayer(placement)
                }

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
                    .frame(width: canvas.width, height: canvas.height)
                    .offset(x: canvas.minX, y: canvas.minY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }

    private func sourceLayer(_ placement: SceneRenderLayerPlacement) -> some View {
        let shape = RoundedRectangle(cornerRadius: placement.cornerRadius, style: .continuous)
        let isScreen = placement.kind == .screen
        let shadowEnabled = isScreen ? scene.screenShadowEnabled : scene.cameraShadowEnabled
        return BlitzSceneThumbnailLayer(kind: placement.kind)
            .clipShape(shape)
            .shadow(color: shadowEnabled ? .black.opacity(0.55) : .clear, radius: 1.5, y: 1)
            .frame(width: placement.targetRect.width, height: placement.targetRect.height)
            .offset(x: placement.targetRect.minX, y: placement.targetRect.minY)
    }

    private func fittedCanvas(in size: CGSize) -> CGRect {
        let available = CGSize(width: max(1, size.width), height: max(1, size.height))
        let ratio = max(0.01, canvasAspectRatio)
        let availableRatio = available.width / available.height
        let canvasSize: CGSize
        if availableRatio > ratio {
            canvasSize = CGSize(width: available.height * ratio, height: available.height)
        } else {
            canvasSize = CGSize(width: available.width, height: available.width / ratio)
        }
        return CGRect(
            x: (available.width - canvasSize.width) / 2,
            y: (available.height - canvasSize.height) / 2,
            width: canvasSize.width,
            height: canvasSize.height
        )
    }
}

enum EditorSceneTitle {
    static func title(for snapshot: RecordingProject.SceneSnapshot) -> String {
        let layerOrder = snapshot.sceneLayout.layerOrder.compactMap(SceneLayerKind.init(rawValue:))
        let sourceOpacities = Dictionary(uniqueKeysWithValues: snapshot.sourceOpacities.compactMap { key, value in
            CaptureSource(rawValue: key).map { ($0, CGFloat(value)) }
        })
        let scene = RecordingScene(
            enabledSources: Set(snapshot.enabledSources.compactMap(CaptureSource.init(rawValue:))),
            sceneLayout: SceneLayout(
                screenFrame: CGRect(
                    x: snapshot.sceneLayout.screenFrame.x,
                    y: snapshot.sceneLayout.screenFrame.y,
                    width: snapshot.sceneLayout.screenFrame.width,
                    height: snapshot.sceneLayout.screenFrame.height
                ),
                cameraFrame: CGRect(
                    x: snapshot.sceneLayout.cameraFrame.x,
                    y: snapshot.sceneLayout.cameraFrame.y,
                    width: snapshot.sceneLayout.cameraFrame.width,
                    height: snapshot.sceneLayout.cameraFrame.height
                ),
                layerOrder: layerOrder.isEmpty ? [.screen, .camera] : layerOrder
            ),
            screenCropAmount: snapshot.screenCropAmount.map {
                CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
            } ?? .zero,
            screenCropPosition: snapshot.screenCropPosition.map {
                CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
            } ?? .zero,
            screenContentMode: snapshot.screenContentMode.flatMap(CameraContentMode.init(rawValue:)) ?? .fill,
            cameraContentMode: CameraContentMode(rawValue: snapshot.cameraContentMode) ?? .fill,
            sourceOpacities: sourceOpacities
        )
        return title(for: scene)
    }

    static func title(for scene: RecordingScene) -> String {
        let canvas = CGRect(x: 0, y: 0, width: 1, height: 1)
        let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)
        let activeKinds = geometry.activeLayerOrder.filter { scene.renderedSources.contains($0.source) }
        if let topKind = activeKinds.last,
           geometry.isFullCanvasFrame(for: topKind) {
            return title(hasScreen: topKind == .screen, hasCamera: topKind == .camera)
        }
        return title(
            hasScreen: activeKinds.contains(.screen),
            hasCamera: activeKinds.contains(.camera)
        )
    }

    private static func title(hasScreen: Bool, hasCamera: Bool) -> String {
        switch (hasScreen, hasCamera) {
        case (true, true): return "Screen + Camera"
        case (true, false): return "Screen"
        case (false, true): return "Camera"
        case (false, false): return "Scene"
        }
    }
}
