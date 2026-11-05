import AppKit
import AVFoundation
import CoreImage
import QuartzCore

final class CameraPreviewView: NSView {
    private let unavailableOverlay = PreviewUnavailableOverlay(kind: .camera)
    private let imageLayer = CALayer()
    private let popoutPreview = CameraPopoutPreview()
    private var popoutIsRendering = false
    private var popoutRevision = 0
    private var latestPopoutInput: CIImage?
    var onPopoutChanged: ((Bool) -> Void)? {
        didSet { onPopoutChanged?(usesRenderedPicture) }
    }
    private var displayedPicture: CVPixelBuffer?
    private var pendingStill: (@MainActor (CGImage?) -> Void)?
    var grade = CameraColorGrade.neutral {
        didSet {
            guard grade != oldValue else { return }
            popoutRevision &+= 1
            noteRenderedPictureChange(wasRendered: popoutStyle != nil || !oldValue.isNeutral)
            refreshRenderedPicture()
        }
    }
    private var usesRenderedPicture: Bool { popoutStyle != nil || !grade.isNeutral }
    var popoutStyle: CameraPopoutStyle? {
        didSet {
            guard popoutStyle != oldValue else { return }
            popoutRevision &+= 1
            noteRenderedPictureChange(wasRendered: oldValue != nil || !grade.isNeutral)
            refreshRenderedPicture()
        }
    }
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var previewLayerHasFrame = false
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private var sourceAspectRatio: CGFloat = SceneLayout.cameraAspectRatio {
        didSet { if oldValue != sourceAspectRatio { syncPreviewLayerFrame() } }
    }
    var sourceCropAmount: CGPoint = .zero {
        didSet {
            guard oldValue != sourceCropAmount else { return }
            syncPreviewLayerFrame()
        }
    }
    var sourceCropPosition: CGPoint = .zero {
        didSet {
            guard oldValue != sourceCropPosition else { return }
            syncPreviewLayerFrame()
        }
    }
    var contentMode: VideoRenderContentMode = .aspectFill {
        didSet { syncPreviewLayerFrame() }
    }
    var usesCapturePreviewLayer: Bool { previewLayer != nil }
    var hasPreviewContent: Bool {
        (previewLayer != nil && previewLayerHasFrame) || sampleBufferLayer != nil || imageLayer.contents != nil
    }
    var currentSourceAspectRatio: CGFloat { sourceAspectRatio }
    private(set) var captureSourceSize: CGSize?
    private(set) var capturePictureSize: CGSize?
    var messageFrameForTesting: CGRect { unavailableOverlay.convert(unavailableOverlay.messageFrameForTesting, to: self) }
    var messageBackgroundFrameForTesting: CGRect { unavailableOverlay.frame }
    var isUnavailableOverlayHiddenForTesting: Bool { unavailableOverlay.isHidden }

    init() {
        super.init(frame: .zero)
        installPreviewBaseLayers(.init(imageLayer: imageLayer, overlay: unavailableOverlay, masksToBounds: true))
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
        layer.isHidden = usesRenderedPicture
        popoutRevision &+= 1
        latestPopoutInput = nil
        previewLayerHasFrame = false
        imageLayer.contents = nil
        sourceAspectRatio = Self.sourceAspectRatio(for: layer) ?? SceneLayout.cameraAspectRatio
        layer.videoGravity = .resizeAspectFill
        layer.actions = previewLayerNoResizeActions
        syncPreviewLayerFrame()
        self.layer?.insertSublayer(layer, at: 0)
        unavailableOverlay.apply(message: "Starting camera")
    }

    func noteCaptureFrame(_ sampleBuffer: CMSampleBuffer) {
        guard previewLayer != nil,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        previewLayerHasFrame = true
        captureSourceSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let plan = CameraFrameLetterboxDetector.normalizationPlan(.init(pixelBuffer: pixelBuffer))
        let width = plan?.outputSize.width ?? CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = plan?.outputSize.height ?? CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        capturePictureSize = CGSize(width: width, height: height)
        sourceAspectRatio = width / max(1, height)
        if usesRenderedPicture || pendingStill != nil {
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let picture = plan.map { image.cropped(to: $0.cropRect) } ?? image
            deliverStill(picture)
            if usesRenderedPicture { renderPicture(picture) }
        }
        hideUnavailableOverlay()
    }

    func setPreviewImage(_ image: CGImage, sourceAspectRatio overrideAspectRatio: CGFloat? = nil) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        deliverStill(CIImage(cgImage: image))
        if usesRenderedPicture {
            renderPicture(CIImage(cgImage: image))
        } else {
            imageLayer.contents = image
        }
        sourceAspectRatio = overrideAspectRatio ?? CGFloat(image.width) / max(1, CGFloat(image.height))
        syncPreviewLayerFrame()
        hideUnavailableOverlay()
    }

    func enqueuePreviewSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        width: Int,
        height: Int,
        sourceAspectRatio overrideAspectRatio: CGFloat? = nil
    ) {
        if pendingStill != nil, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            deliverStill(CIImage(cvPixelBuffer: buffer))
        }
        if usesRenderedPicture, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            sampleBufferLayer?.isHidden = true
            sourceAspectRatio = overrideAspectRatio ?? CGFloat(width) / max(1, CGFloat(height))
            renderPicture(CIImage(cvPixelBuffer: buffer))
            syncPreviewLayerFrame()
            hideUnavailableOverlay()
            return
        }
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        imageLayer.contents = nil
        if sampleBufferLayer == nil {
            let layer = AVSampleBufferDisplayLayer.previewDisplayLayer(backgroundColor: NSColor.black.cgColor)
            sampleBufferLayer = layer
            self.layer?.insertSublayer(layer, at: 0)
        }
        sampleBufferLayer?.isHidden = false
        sourceAspectRatio = overrideAspectRatio ?? CGFloat(width) / max(1, CGFloat(height))
        syncPreviewLayerFrame()
        hideUnavailableOverlay()
        sampleBufferLayer?.enqueuePreviewFrame(sampleBuffer)
    }

    func setSourceAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0 else { return }
        sourceAspectRatio = aspectRatio
    }

    func setMessage(_ message: String) {
        popoutRevision &+= 1
        latestPopoutInput = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = nil
        unavailableOverlay.apply(message: message)
    }

    func requestStillFrame(_ handler: @escaping @MainActor (CGImage?) -> Void) {
        pendingStill = handler
    }

    private func deliverStill(_ image: CIImage) {
        guard let handler = pendingStill else { return }
        pendingStill = nil
        popoutPreview.still(.init(image: image, maxDimension: 320, completion: handler))
    }

    private func noteRenderedPictureChange(wasRendered: Bool) {
        if wasRendered != usesRenderedPicture { onPopoutChanged?(usesRenderedPicture) }
    }

    private func refreshRenderedPicture() {
        previewLayer?.isHidden = usesRenderedPicture
        sampleBufferLayer?.isHidden = usesRenderedPicture
        if !usesRenderedPicture {
            imageLayer.contents = nil
        } else if let latestPopoutInput {
            renderPicture(latestPopoutInput)
        }
    }

    private func renderPicture(_ image: CIImage) {
        latestPopoutInput = image
        guard !popoutIsRendering, usesRenderedPicture else { return }
        popoutIsRendering = true
        let revision = popoutRevision
        let style = popoutStyle
        popoutPreview.render(.init(
            image: image, grade: grade, style: style, maxDimension: style == nil ? 1_920 : 960,
            completion: { [weak self] picture in
                guard let self else { return }
                self.popoutIsRendering = false
                guard self.popoutRevision == revision, self.usesRenderedPicture else { return }
                self.displayedPicture = picture
                self.imageLayer.contents = picture.flatMap { CVPixelBufferGetIOSurface($0)?.takeUnretainedValue() }
            }
        ))
    }

    /// Keeps the last frame on screen, dimmed, while idle previews pause in the background.
    func showPaused() {
        unavailableOverlay.apply(message: "Paused")
    }

    private func hideUnavailableOverlay() {
        unavailableOverlay.apply(message: "")
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
