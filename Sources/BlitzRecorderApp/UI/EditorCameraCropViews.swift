import AppKit
import SwiftUI

enum EditorCameraCropInteractionKind: Equatable {
    case move
    case resize(ResizeAnchor)
}

struct EditorCameraCropInteractionChange {
    let kind: EditorCameraCropInteractionKind
    let delta: CGPoint
    let startControl: CameraCropControl
}

struct EditorCameraCropOverlayConfiguration {
    let scene: RecordingScene
    let renderSize: CGSize
    let sourceAspectRatio: CGFloat
    let onChange: (EditorCameraCropInteractionChange) -> Void
    let onDone: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
}

struct EditorCameraCropOverlay: View {
    let configuration: EditorCameraCropOverlayConfiguration

    var body: some View {
        GeometryReader { proxy in
            if let presentation = EditorCameraCropPresentation.make(.init(
                containerSize: proxy.size,
                renderSize: configuration.renderSize,
                scene: configuration.scene,
                sourceAspectRatio: configuration.sourceAspectRatio
            )) {
                EditorCameraCropSelectionOverlay(presentation: presentation)

                EditorCameraCropInteractionView(configuration: .init(
                    presentation: presentation,
                    control: CameraCropControl(
                        amount: configuration.scene.cameraCropAmount,
                        position: configuration.scene.cameraCropPosition
                    ),
                    onChange: configuration.onChange
                ))
            }
        }
        .overlay(alignment: .bottom) {
            CropFloatingToolbar(configuration: .init(
                onDone: configuration.onDone,
                onReset: configuration.onReset,
                onCancel: configuration.onCancel
            ))
            .fixedSize()
            .padding(.bottom, 12)
        }
    }
}

struct EditorCameraCropSelectionOverlay: View {
    let presentation: EditorCameraCropPresentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(presentation.sourceFrame)
                path.addRect(presentation.cropFrame)
            }
            .fill(.black.opacity(0.48), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(.white.opacity(0.34), lineWidth: 1)
                .frame(width: presentation.sourceFrame.width, height: presentation.sourceFrame.height)
                .offset(x: presentation.sourceFrame.minX, y: presentation.sourceFrame.minY)

            Rectangle()
                .stroke(BlitzUI.mint, lineWidth: 2)
                .frame(width: presentation.cropFrame.width, height: presentation.cropFrame.height)
                .overlay { cropHandles }
                .offset(x: presentation.cropFrame.minX, y: presentation.cropFrame.minY)
        }
        .allowsHitTesting(false)
    }

    private var cropHandles: some View {
        ZStack {
            cropHandle(alignment: .topLeading)
            cropHandle(alignment: .topTrailing)
            cropHandle(alignment: .bottomLeading)
            cropHandle(alignment: .bottomTrailing)
        }
    }

    private func cropHandle(alignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(BlitzUI.mint)
            .frame(width: 12, height: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.black.opacity(0.9), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(
                x: alignment.horizontal == .leading ? -6 : 6,
                y: alignment.vertical == .top ? -6 : 6
            )
    }
}

struct EditorCameraCropInteractionConfiguration {
    let presentation: EditorCameraCropPresentation
    let control: CameraCropControl
    let onChange: (EditorCameraCropInteractionChange) -> Void
}

struct EditorCameraCropInteractionView: NSViewRepresentable {
    let configuration: EditorCameraCropInteractionConfiguration

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.presentation = configuration.presentation
        view.control = configuration.control
        view.onChange = configuration.onChange
    }

    final class InteractionView: NSView {
        private struct ResizeAnchorRequest {
            let point: CGPoint
            let frame: CGRect
        }

        var presentation: EditorCameraCropPresentation?
        var control = CameraCropControl(amount: .zero, position: .zero)
        var onChange: ((EditorCameraCropInteractionChange) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragKind: EditorCameraCropInteractionKind?
        private var dragStart = CGPoint.zero
        private var dragStartControl = CameraCropControl(amount: .zero, position: .zero)

        override var isFlipped: Bool { true }

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

        override func mouseDown(with event: NSEvent) {
            guard let presentation else { return }
            let point = convert(event.locationInWindow, from: nil)
            let kind: EditorCameraCropInteractionKind?
            if let anchor = resizeAnchor(.init(point: point, frame: presentation.cropFrame)) {
                kind = .resize(anchor)
                anchor.cursor.set()
            } else if presentation.cropFrame.contains(point) {
                kind = .move
                NSCursor.closedHand.set()
            } else {
                kind = nil
            }
            dragKind = kind
            dragStart = point
            dragStartControl = control
        }

        override func mouseDragged(with event: NSEvent) {
            sendChange(event)
        }

        override func mouseUp(with event: NSEvent) {
            sendChange(event)
            dragKind = nil
            updateCursor(event)
        }

        override func mouseMoved(with event: NSEvent) {
            guard dragKind == nil else { return }
            updateCursor(event)
        }

        override func mouseExited(with event: NSEvent) {
            guard dragKind == nil else { return }
            NSCursor.arrow.set()
        }

        private func sendChange(_ event: NSEvent) {
            guard let dragKind, let presentation else { return }
            let point = convert(event.locationInWindow, from: nil)
            let scale = max(0.0001, presentation.pointsPerRenderUnit)
            onChange?(EditorCameraCropInteractionChange(
                kind: dragKind,
                delta: CGPoint(
                    x: (point.x - dragStart.x) / scale,
                    y: (point.y - dragStart.y) / scale
                ),
                startControl: dragStartControl
            ))
        }

        private func updateCursor(_ event: NSEvent) {
            guard let presentation else {
                NSCursor.arrow.set()
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            if let anchor = resizeAnchor(.init(point: point, frame: presentation.cropFrame)) {
                anchor.cursor.set()
            } else if presentation.cropFrame.contains(point) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }

        private func resizeAnchor(_ request: ResizeAnchorRequest) -> ResizeAnchor? {
            let size: CGFloat = 18
            let half = size / 2
            let frame = request.frame
            let targets: [(ResizeAnchor, CGRect)] = [
                (.topLeft, CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size)),
                (.topRight, CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)),
                (.bottomLeft, CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size)),
                (.bottomRight, CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size))
            ]
            return targets.first(where: { $0.1.contains(request.point) })?.0
        }
    }
}
