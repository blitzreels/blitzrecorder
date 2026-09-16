import AppKit
import AVFoundation
import QuartzCore

final class CameraPreviewView: NSView {
    private let unavailableOverlay = PreviewUnavailableOverlay(kind: .camera)
    private let imageLayer = CALayer()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private var sourceAspectRatio: CGFloat = SceneLayout.cameraAspectRatio {
        didSet { syncPreviewLayerFrame() }
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
    var hasPreviewContent: Bool { previewLayer != nil || sampleBufferLayer != nil || imageLayer.contents != nil }
    var currentSourceAspectRatio: CGFloat { sourceAspectRatio }
    var messageFrameForTesting: CGRect { unavailableOverlay.convert(unavailableOverlay.messageFrameForTesting, to: self) }
    var messageBackgroundFrameForTesting: CGRect { unavailableOverlay.frame }
    var isUnavailableOverlayHiddenForTesting: Bool { unavailableOverlay.isHidden }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = true
        layer?.actions = previewLayerNoResizeActions

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.backgroundColor = .clear
        imageLayer.actions = previewLayerNoResizeActions
        layer?.addSublayer(imageLayer)

        unavailableOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(unavailableOverlay)
        NSLayoutConstraint.activate([
            unavailableOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            unavailableOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            unavailableOverlay.topAnchor.constraint(equalTo: topAnchor),
            unavailableOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
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
        layer.actions = previewLayerNoResizeActions
        syncPreviewLayerFrame()
        self.layer?.insertSublayer(layer, at: 0)
        hideUnavailableOverlay()
    }

    func setPreviewImage(_ image: CGImage, sourceAspectRatio overrideAspectRatio: CGFloat? = nil) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = image
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
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        imageLayer.contents = nil
        if sampleBufferLayer == nil {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspectFill
            layer.actions = previewLayerNoResizeActions
            layer.backgroundColor = NSColor.black.cgColor
            sampleBufferLayer = layer
            self.layer?.insertSublayer(layer, at: 0)
        }
        sourceAspectRatio = overrideAspectRatio ?? CGFloat(width) / max(1, CGFloat(height))
        syncPreviewLayerFrame()
        hideUnavailableOverlay()
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
        unavailableOverlay.apply(message: message)
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
