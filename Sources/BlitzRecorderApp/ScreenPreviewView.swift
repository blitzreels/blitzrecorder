import AppKit
import AVFoundation
import QuartzCore

final class ScreenPreviewView: NSView {
    private let imageLayer = CALayer()
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private let unavailableOverlay = PreviewUnavailableOverlay(kind: .screen)
    private var pendingStill: (@MainActor (CGImage?) -> Void)?
    private var isPaused = false

    /// Frames are arriving, so a still can come from the next one instead of a new screen capture.
    var showsLiveFrames: Bool { sampleBufferLayer != nil && !isPaused }

    var hasPreviewContent: Bool { sampleBufferLayer != nil || imageLayer.contents != nil }
    var messageFrameForTesting: CGRect { unavailableOverlay.convert(unavailableOverlay.messageFrameForTesting, to: self) }
    var messageBackgroundFrameForTesting: CGRect { unavailableOverlay.frame }
    var isUnavailableOverlayHiddenForTesting: Bool { unavailableOverlay.isHidden }

    init() {
        super.init(frame: .zero)
        installPreviewBaseLayers(.init(imageLayer: imageLayer, overlay: unavailableOverlay, masksToBounds: false))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        syncLayerFrames()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncLayerFrames()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        syncLayerFrames()
    }

    private func syncLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        sampleBufferLayer?.frame = bounds
        CATransaction.commit()
    }

    func requestStillFrame(_ handler: @escaping @MainActor (CGImage?) -> Void) {
        pendingStill = handler
    }

    func setImage(_ image: CGImage) {
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        hideUnavailableOverlay()
        imageLayer.contents = image
    }

    func enqueuePreviewSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        imageLayer.contents = nil
        if sampleBufferLayer == nil {
            let layer = AVSampleBufferDisplayLayer.previewDisplayLayer(backgroundColor: NSColor.clear.cgColor)
            sampleBufferLayer = layer
            self.layer?.insertSublayer(layer, at: 0)
            syncLayerFrames()
        }
        sampleBufferLayer?.enqueuePreviewFrame(sampleBuffer)
        isPaused = false
        hideUnavailableOverlay()
        deliverStill(sampleBuffer)
    }

    private func deliverStill(_ sampleBuffer: CMSampleBuffer) {
        guard let handler = pendingStill, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        pendingStill = nil
        StillImageRenderer.renderOffMain(.init(
            still: .init(image: CIImage(cvPixelBuffer: pixels), maxSize: CGSize(width: 480, height: 300)),
            completion: handler
        ))
    }

    func setMessage(_ message: String) {
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = nil
        unavailableOverlay.apply(message: message)
    }

    /// Keeps the last frame on screen, dimmed, while idle previews pause in the background.
    func showPaused() {
        isPaused = true
        unavailableOverlay.apply(message: "Paused")
    }

    private func hideUnavailableOverlay() {
        unavailableOverlay.apply(message: "")
    }
}

