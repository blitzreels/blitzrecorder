import AppKit
import AVFoundation
import QuartzCore

struct PreviewBaseLayersRequest {
    let imageLayer: CALayer
    let overlay: PreviewUnavailableOverlay
    let masksToBounds: Bool
}

extension NSView {
    func installPreviewBaseLayers(_ request: PreviewBaseLayersRequest) {
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = request.masksToBounds
        layer?.actions = previewLayerNoResizeActions

        request.imageLayer.contentsGravity = .resizeAspectFill
        request.imageLayer.backgroundColor = .clear
        request.imageLayer.actions = previewLayerNoResizeActions
        layer?.addSublayer(request.imageLayer)

        let overlay = request.overlay
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

extension AVSampleBufferDisplayLayer {
    static func previewDisplayLayer(backgroundColor: CGColor) -> AVSampleBufferDisplayLayer {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspectFill
        layer.actions = previewLayerNoResizeActions
        layer.backgroundColor = backgroundColor
        return layer
    }

    func enqueuePreviewFrame(_ sampleBuffer: CMSampleBuffer) {
        if #available(macOS 15.0, *) {
            let renderer = sampleBufferRenderer
            if renderer.status == .failed {
                renderer.flush()
            }
            if renderer.isReadyForMoreMediaData {
                renderer.enqueue(sampleBuffer)
            }
        } else {
            if status == .failed {
                flush()
            }
            if isReadyForMoreMediaData {
                enqueue(sampleBuffer)
            }
        }
    }
}
