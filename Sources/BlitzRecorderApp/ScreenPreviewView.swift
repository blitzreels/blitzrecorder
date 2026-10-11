import AppKit
import AVFoundation
import QuartzCore

final class ScreenPreviewView: NSView {
    private let imageLayer = CALayer()
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private let unavailableOverlay = PreviewUnavailableOverlay(kind: .screen)

    var hasPreviewContent: Bool { sampleBufferLayer != nil || imageLayer.contents != nil }
    var messageFrameForTesting: CGRect { unavailableOverlay.convert(unavailableOverlay.messageFrameForTesting, to: self) }
    var messageBackgroundFrameForTesting: CGRect { unavailableOverlay.frame }
    var isUnavailableOverlayHiddenForTesting: Bool { unavailableOverlay.isHidden }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = false
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

    func setImage(_ image: CGImage) {
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        hideUnavailableOverlay()
        imageLayer.contents = image
    }

    func enqueuePreviewSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        imageLayer.contents = nil
        if sampleBufferLayer == nil {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspectFill
            layer.actions = previewLayerNoResizeActions
            layer.backgroundColor = NSColor.clear.cgColor
            sampleBufferLayer = layer
            self.layer?.insertSublayer(layer, at: 0)
            syncLayerFrames()
        }
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
        hideUnavailableOverlay()
    }

    func setMessage(_ message: String) {
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        imageLayer.contents = nil
        unavailableOverlay.apply(message: message)
    }

    private func hideUnavailableOverlay() {
        unavailableOverlay.apply(message: "")
    }
}

