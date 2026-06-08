import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewFocusPoint: Sendable {
    var layerPoint: CGPoint
    var metadataPoint: CGPoint
}

enum CameraCinematicFocusMode: Int, Sendable {
    case none = 0
    case strong = 1
    case weak = 2
}

struct CameraCinematicFocusCandidate: Equatable, Identifiable, Sendable {
    var objectID: Int
    var metadataBounds: CGRect
    var focusMode: CameraCinematicFocusMode

    var id: Int { objectID }

    func contains(_ point: CGPoint) -> Bool {
        metadataBounds.contains(point)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var focusCandidates: [CameraCinematicFocusCandidate] = []
    var onTap: (CameraPreviewFocusPoint) -> Void = { _ in }
    var onLongPress: (CameraPreviewFocusPoint) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.setFocusCandidates(focusCandidates)
        context.coordinator.installGestures(on: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        uiView.videoPreviewLayer.session = session
        uiView.setFocusCandidates(focusCandidates)
    }

    final class Coordinator: NSObject {
        var onTap: (CameraPreviewFocusPoint) -> Void
        var onLongPress: (CameraPreviewFocusPoint) -> Void

        init(
            onTap: @escaping (CameraPreviewFocusPoint) -> Void,
            onLongPress: @escaping (CameraPreviewFocusPoint) -> Void
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        func installGestures(on view: PreviewView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            view.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.35
            longPress.cancelsTouchesInView = false
            view.addGestureRecognizer(longPress)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let point = focusPoint(from: recognizer) else {
                return
            }
            onTap(point)
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let point = focusPoint(from: recognizer) else {
                return
            }
            onLongPress(point)
        }

        private func focusPoint(from recognizer: UIGestureRecognizer) -> CameraPreviewFocusPoint? {
            guard let view = recognizer.view as? PreviewView else { return nil }
            let location = recognizer.location(in: view)
            let metadataRect = view.videoPreviewLayer.metadataOutputRectConverted(
                fromLayerRect: CGRect(origin: location, size: .zero)
            )
            return CameraPreviewFocusPoint(
                layerPoint: location,
                metadataPoint: CGPoint(
                    x: min(1, max(0, metadataRect.origin.x)),
                    y: min(1, max(0, metadataRect.origin.y))
                )
            )
        }
    }
}

final class PreviewView: UIView {
    private let focusOverlayLayer = CALayer()
    private var focusCandidateLayers: [Int: CAShapeLayer] = [:]
    private var focusCandidates: [CameraCinematicFocusCandidate] = []

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        installFocusOverlayLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installFocusOverlayLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        focusOverlayLayer.frame = bounds
        updateFocusOverlay()
    }

    func setFocusCandidates(_ candidates: [CameraCinematicFocusCandidate]) {
        guard focusCandidates != candidates else { return }
        focusCandidates = candidates
        updateFocusOverlay()
    }

    private func installFocusOverlayLayer() {
        focusOverlayLayer.frame = bounds
        focusOverlayLayer.masksToBounds = true
        videoPreviewLayer.addSublayer(focusOverlayLayer)
    }

    private func updateFocusOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let activeIDs = Set(focusCandidates.map(\.objectID))
        let staleIDs = focusCandidateLayers.keys.filter { !activeIDs.contains($0) }
        for id in staleIDs {
            guard let layer = focusCandidateLayers[id] else { continue }
            layer.removeFromSuperlayer()
            focusCandidateLayers[id] = nil
        }

        for candidate in focusCandidates {
            let rect = videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: candidate.metadataBounds)
            guard rect.intersects(bounds), rect.width > 2, rect.height > 2 else {
                focusCandidateLayers[candidate.objectID]?.isHidden = true
                continue
            }

            let shapeLayer = focusCandidateLayers[candidate.objectID] ?? makeFocusCandidateLayer()
            if focusCandidateLayers[candidate.objectID] == nil {
                focusOverlayLayer.addSublayer(shapeLayer)
                focusCandidateLayers[candidate.objectID] = shapeLayer
            }

            shapeLayer.isHidden = false
            shapeLayer.frame = rect
            shapeLayer.path = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: rect.size),
                cornerRadius: 8
            ).cgPath
            shapeLayer.strokeColor = focusStrokeColor(for: candidate.focusMode).cgColor
            shapeLayer.lineDashPattern = focusLineDashPattern(for: candidate.focusMode)
        }
    }

    private func makeFocusCandidateLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 3
        layer.shadowOffset = .zero
        return layer
    }

    private func focusStrokeColor(for mode: CameraCinematicFocusMode) -> UIColor {
        switch mode {
        case .strong, .weak:
            return UIColor(red: 1, green: 0.88, blue: 0.18, alpha: 1)
        case .none:
            return UIColor(white: 1, alpha: 0.82)
        }
    }

    private func focusLineDashPattern(for mode: CameraCinematicFocusMode) -> [NSNumber]? {
        switch mode {
        case .weak:
            return [6, 5]
        case .none, .strong:
            return nil
        }
    }
}
