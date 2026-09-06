import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

struct EditorDisplayLinkRequest {
    let isAttachedToWindow: Bool
    let isPlaying: Bool
}

enum EditorDisplayLinkPolicy {
    static func shouldRun(_ request: EditorDisplayLinkRequest) -> Bool {
        request.isAttachedToWindow && request.isPlaying
    }
}

private struct EditorCameraCropCanvasFrameRequest {
    let scene: RecordingScene
    let aspectRatios: [SceneLayerKind: CGFloat]
}

@MainActor
struct EditorCompositedPlayer: NSViewRepresentable {
    let controller: EditorPlaybackController
    let renderSize: CGSize
    let previewSceneRevision: Int
    let cameraCropEditingScene: RecordingScene?

    func makeNSView(context: Context) -> EditorCompositedPlayerView {
        let view = EditorCompositedPlayerView()
        view.controller = controller
        view.cameraCropEditingScene = cameraCropEditingScene
        view.configure(renderSize: renderSize)
        return view
    }

    func updateNSView(_ nsView: EditorCompositedPlayerView, context: Context) {
        nsView.controller = controller
        nsView.previewSceneRevision = previewSceneRevision
        nsView.cameraCropEditingScene = cameraCropEditingScene
        nsView.configure(renderSize: renderSize)
        nsView.refresh()
        nsView.synchronizeDisplayLink()
    }

    static func dismantleNSView(_ nsView: EditorCompositedPlayerView, coordinator: ()) {
        nsView.teardown()
    }
}

@MainActor
final class EditorCompositedPlayerView: NSView {
    private let canvasLayer = CALayer()
    private let backgroundLayer = CALayer()

    private struct SourceLayers {
        let clip = CALayer()
        let shadowHost = CALayer()
        let playerLayer = AVPlayerLayer()
    }

    private struct RenderState: Equatable {
        let scene: RecordingScene
        let canvasFrame: CGRect
        let renderSize: CGSize
        let backingScaleFactor: CGFloat
        let aspectRatios: [SceneLayerKind: CGFloat]
        let hiddenKinds: Set<SceneLayerKind>
        let isCameraCropEditing: Bool
        let screenPlayer: ObjectIdentifier?
        let cameraPlayer: ObjectIdentifier?
    }

    private var sourceLayers: [SceneLayerKind: SourceLayers] = [:]
    private var renderedState: RenderState?
    private var renderSize: CGSize = .zero
    private var renderedBackgroundKey: (style: CanvasBackgroundStyle, width: Int, height: Int)?
    var previewSceneRevision = 0
    var cameraCropEditingScene: RecordingScene?

    weak var controller: EditorPlaybackController?
    private var displayLink: CADisplayLink?

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        canvasLayer.isGeometryFlipped = true
        canvasLayer.masksToBounds = false
        canvasLayer.actions = disabledActions
        backgroundLayer.actions = disabledActions
        backgroundLayer.contentsGravity = .resize
        backgroundLayer.masksToBounds = true
        canvasLayer.addSublayer(backgroundLayer)
        layer?.addSublayer(canvasLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var disabledActions: [String: any CAAction] {
        ["frame": NSNull(), "bounds": NSNull(), "position": NSNull(), "contents": NSNull(), "path": NSNull()]
    }

    func configure(renderSize: CGSize) {
        guard self.renderSize != renderSize else { return }
        self.renderSize = renderSize
        needsLayout = true
    }

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func synchronizeDisplayLink() {
        let shouldRun = EditorDisplayLinkPolicy.shouldRun(EditorDisplayLinkRequest(
            isAttachedToWindow: window != nil,
            isPlaying: controller?.isPlaying == true
        ))
        if shouldRun {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    @objc private func tick() {
        refresh()
        synchronizeDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeDisplayLink()
    }

    override func layout() {
        super.layout()
        refresh()
    }

    private func aspectFitCanvasFrame() -> CGRect {
        guard renderSize.width > 0, renderSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / renderSize.width, bounds.height / renderSize.height)
        let size = CGSize(width: renderSize.width * scale, height: renderSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func refresh() {
        guard let controller, controller.isReady, renderSize.width > 0, renderSize.height > 0 else { return }
        let time = controller.displayTime()
        guard let playbackScene = controller.scene(at: time) else { return }
        let scene = cameraCropEditingScene ?? playbackScene
        let canvasFrame = cameraCropCanvasFrame(.init(
            scene: scene,
            aspectRatios: controller.sourceAspectRatios
        ))
        guard canvasFrame.width > 0 else { return }
        let aspectRatios = controller.sourceAspectRatios
        let hidden = controller.hiddenKinds
        let state = RenderState(
            scene: scene,
            canvasFrame: canvasFrame,
            renderSize: renderSize,
            backingScaleFactor: window?.backingScaleFactor ?? 2,
            aspectRatios: aspectRatios,
            hiddenKinds: hidden,
            isCameraCropEditing: cameraCropEditingScene != nil,
            screenPlayer: controller.videoPlayer(for: .screen).map(ObjectIdentifier.init),
            cameraPlayer: controller.videoPlayer(for: .camera).map(ObjectIdentifier.init)
        )
        guard renderedState != state else { return }
        let scale = canvasFrame.width / renderSize.width
        let geometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: renderSize),
            scene: scene,
            origin: .upperLeft
        )
        let activeOrder = geometry.activeLayerOrder.filter { !hidden.contains($0) }

        performWithoutUIAnimation {
            canvasLayer.frame = canvasFrame
            canvasLayer.bounds = CGRect(origin: .zero, size: canvasFrame.size)
            updateBackground(scene: scene, canvasSize: canvasFrame.size)

            for kind in [SceneLayerKind.screen, .camera] {
                guard let player = controller.videoPlayer(for: kind) else {
                    sourceLayers[kind]?.shadowHost.isHidden = true
                    continue
                }
                let layers = sourceLayers[kind] ?? makeSourceLayers(for: kind, player: player)
                if layers.playerLayer.player !== player {
                    layers.playerLayer.player = player
                }
                guard let zIndex = activeOrder.firstIndex(of: kind) else {
                    layers.shadowHost.isHidden = true
                    continue
                }
                layers.shadowHost.isHidden = false
                layers.shadowHost.zPosition = CGFloat(zIndex + 1)
                layoutSource(
                    kind: kind,
                    layers: layers,
                    geometry: geometry,
                    aspectRatios: aspectRatios,
                    scale: scale,
                    scene: scene,
                    isCameraCropEditing: kind == .camera && cameraCropEditingScene != nil
                )
            }
        }
        renderedState = state
    }

    private func cameraCropCanvasFrame(_ request: EditorCameraCropCanvasFrameRequest) -> CGRect {
        guard cameraCropEditingScene != nil,
              let sourceAspectRatio = request.aspectRatios[.camera],
              let presentation = EditorCameraCropPresentation.make(.init(
                containerSize: bounds.size,
                renderSize: renderSize,
                scene: request.scene,
                sourceAspectRatio: sourceAspectRatio
              )) else {
            return aspectFitCanvasFrame()
        }
        return presentation.canvasFrame
    }

    private func makeSourceLayers(for kind: SceneLayerKind, player: AVPlayer) -> SourceLayers {
        let layers = SourceLayers()
        layers.shadowHost.actions = disabledActions
        layers.shadowHost.masksToBounds = false
        layers.clip.actions = disabledActions
        layers.clip.isGeometryFlipped = true
        layers.clip.masksToBounds = true
        layers.playerLayer.actions = disabledActions
        layers.playerLayer.videoGravity = .resize
        layers.playerLayer.player = player
        layers.clip.addSublayer(layers.playerLayer)
        layers.shadowHost.addSublayer(layers.clip)
        canvasLayer.addSublayer(layers.shadowHost)
        sourceLayers[kind] = layers
        return layers
    }

    private func layoutSource(
        kind: SceneLayerKind,
        layers: SourceLayers,
        geometry: SceneRenderGeometry,
        aspectRatios: [SceneLayerKind: CGFloat],
        scale: CGFloat,
        scene: RecordingScene,
        isCameraCropEditing: Bool
    ) {
        let targetRect = geometry.targetRect(for: kind)
        let aspect = aspectRatios[kind] ?? (targetRect.height > 0 ? targetRect.width / targetRect.height : 1)
        if isCameraCropEditing {
            let sourceFrame = geometry.cameraCropSourceFrame(sourceAspectRatio: aspect)
            let displayedFrame = CGRect(
                x: sourceFrame.minX * scale,
                y: sourceFrame.minY * scale,
                width: sourceFrame.width * scale,
                height: sourceFrame.height * scale
            )
            layers.shadowHost.frame = displayedFrame
            layers.shadowHost.shadowOpacity = 0
            layers.clip.frame = CGRect(origin: .zero, size: displayedFrame.size)
            layers.clip.cornerRadius = 0
            layers.playerLayer.frame = layers.clip.bounds
            return
        }
        let sourceFrame = geometry.sourceFrame(
            for: kind,
            sourceAspectRatio: aspect,
            sourceCropAmount: kind == .camera ? scene.cameraCropAmount : scene.screenCropAmount,
            sourceCropPosition: kind == .camera ? scene.cameraCropPosition : scene.screenCropPosition
        )
        let radius = geometry.sourceCornerRadius(for: kind) * scale

        let clipFrame = CGRect(
            x: targetRect.minX * scale,
            y: targetRect.minY * scale,
            width: targetRect.width * scale,
            height: targetRect.height * scale
        )
        layers.shadowHost.frame = clipFrame
        layers.clip.frame = CGRect(origin: .zero, size: clipFrame.size)
        layers.clip.cornerRadius = radius
        layers.playerLayer.frame = CGRect(
            x: (sourceFrame.minX - targetRect.minX) * scale,
            y: (sourceFrame.minY - targetRect.minY) * scale,
            width: sourceFrame.width * scale,
            height: sourceFrame.height * scale
        )

        let shadowEnabled = kind == .screen ? scene.screenShadowEnabled : scene.cameraShadowEnabled
        if shadowEnabled {
            layers.shadowHost.shadowColor = CGColor(gray: 0, alpha: 1)
            layers.shadowHost.shadowRadius = 18 * scale
            layers.shadowHost.shadowOffset = CGSize(width: 0, height: 8 * scale)
            layers.shadowHost.shadowOpacity = 0.45
            layers.shadowHost.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: clipFrame.size),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        } else {
            layers.shadowHost.shadowOpacity = 0
        }
    }

    private func updateBackground(scene: RecordingScene, canvasSize: CGSize) {
        backgroundLayer.frame = CGRect(origin: .zero, size: canvasSize)
        let appearance = scene.canvasBackgroundStyle.appearance
        backgroundLayer.backgroundColor = appearance.solidCGColor
        let scaleFactor = window?.backingScaleFactor ?? 2
        let width = Int((canvasSize.width * scaleFactor).rounded(.up))
        let height = Int((canvasSize.height * scaleFactor).rounded(.up))
        guard width > 0, height > 0 else { return }
        let key = (scene.canvasBackgroundStyle, width, height)
        if renderedBackgroundKey == nil || renderedBackgroundKey! != key {
            backgroundLayer.contents = appearance.renderCGImage(pixelWidth: width, pixelHeight: height)
            renderedBackgroundKey = key
        }
    }

    func teardown() {
        stopDisplayLink()
        renderedState = nil
        for layers in sourceLayers.values {
            layers.playerLayer.player = nil
        }
    }
}
