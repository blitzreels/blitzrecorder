import AppKit
import SwiftUI

struct EditorCanvasInteractionView: NSViewRepresentable {
    let layers: [EditorCanvasLayer]
    @Binding var hoveredLayerID: String?
    let onSelect: (EditorCanvasLayer) -> Void
    let onMove: (SceneLayerKind, CGSize, Bool) -> Void
    let onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.layers = layers
        view.hoveredLayerID = hoveredLayerID
        view.onHover = { hoveredLayerID = $0 }
        view.onSelect = onSelect
        view.onMove = onMove
        view.onResize = onResize
        view.needsDisplay = true
    }

    final class InteractionView: NSView {
        enum DragMode {
            case move(SceneLayerKind)
            case resize(SceneLayerKind, ResizeAnchor)
        }

        var layers: [EditorCanvasLayer] = []
        var hoveredLayerID: String?
        var onHover: ((String?) -> Void)?
        var onSelect: ((EditorCanvasLayer) -> Void)?
        var onMove: ((SceneLayerKind, CGSize, Bool) -> Void)?
        var onResize: ((SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragMode: DragMode?
        private var dragStart: CGPoint = .zero

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

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

        override func mouseMoved(with event: NSEvent) {
            guard dragMode == nil else { return }
            let point = convert(event.locationInWindow, from: nil)
            setHoveredLayer(resizeHit(at: point)?.layer.id ?? hitLayer(at: point)?.id)
            cursor(at: point).set()
        }

        override func mouseExited(with event: NSEvent) {
            guard dragMode == nil else { return }
            setHoveredLayer(nil)
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            dragStart = point
            if let hit = resizeHit(at: point) {
                onSelect?(hit.layer)
                setHoveredLayer(hit.layer.id)
                dragMode = .resize(hit.layer.kind, hit.anchor)
                hit.anchor.cursor.set()
                return
            }
            guard let layer = hitLayer(at: point) else {
                dragMode = nil
                setHoveredLayer(nil)
                return
            }
            onSelect?(layer)
            setHoveredLayer(layer.id)
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                dragMode = .resize(layer.kind, anchor)
                anchor.cursor.set()
            } else if layer.isEditable {
                dragMode = .move(layer.kind)
                NSCursor.closedHand.set()
            } else {
                dragMode = nil
            }
        }

        override func mouseDragged(with event: NSEvent) {
            reportDrag(.init(event: event, ended: false))
        }

        override func mouseUp(with event: NSEvent) {
            guard let point = reportDrag(.init(event: event, ended: true)) else { return }
            dragMode = nil
            cursor(at: point).set()
        }

        private struct DragEvent {
            let event: NSEvent
            let ended: Bool
        }

        @discardableResult
        private func reportDrag(_ drag: DragEvent) -> CGPoint? {
            guard let dragMode else { return nil }
            let point = convert(drag.event.locationInWindow, from: nil)
            let translation = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            switch dragMode {
            case .move(let kind):
                onMove?(kind, translation, drag.ended)
            case .resize(let kind, let anchor):
                onResize?(kind, anchor, translation, drag.ended)
            }
            return point
        }

        private func hitLayer(at point: CGPoint) -> EditorCanvasLayer? {
            layers.reversed().first { frame(for: $0).contains(point) }
        }

        private func resizeHit(at point: CGPoint) -> (layer: EditorCanvasLayer, anchor: ResizeAnchor)? {
            for layer in layers.reversed() where layer.isSelected && layer.isEditable {
                if let anchor = resizeAnchor(at: point, in: layer) {
                    return (layer, anchor)
                }
            }
            return nil
        }

        private func frame(for layer: EditorCanvasLayer) -> CGRect {
            CGRect(
                x: layer.frame.minX * bounds.width,
                y: layer.frame.minY * bounds.height,
                width: layer.frame.width * bounds.width,
                height: layer.frame.height * bounds.height
            )
        }

        private func resizeAnchor(at point: CGPoint, in layer: EditorCanvasLayer) -> ResizeAnchor? {
            let frame = frame(for: layer)
            let size: CGFloat = 18
            let half = size / 2
            let cornerHandles: [(ResizeAnchor, CGRect)] = [
                (.topLeft, CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size)),
                (.topRight, CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)),
                (.bottomLeft, CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size)),
                (.bottomRight, CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size))
            ]
            if let corner = cornerHandles.first(where: { $0.1.contains(point) }) {
                return corner.0
            }

            let edgeThickness: CGFloat = 16
            let edgeHalf = edgeThickness / 2
            let edgeHandles: [(ResizeAnchor, CGRect)] = [
                (.top, CGRect(
                    x: frame.minX + half,
                    y: frame.minY - edgeHalf,
                    width: max(0, frame.width - size),
                    height: edgeThickness
                )),
                (.right, CGRect(
                    x: frame.maxX - edgeHalf,
                    y: frame.minY + half,
                    width: edgeThickness,
                    height: max(0, frame.height - size)
                )),
                (.bottom, CGRect(
                    x: frame.minX + half,
                    y: frame.maxY - edgeHalf,
                    width: max(0, frame.width - size),
                    height: edgeThickness
                )),
                (.left, CGRect(
                    x: frame.minX - edgeHalf,
                    y: frame.minY + half,
                    width: edgeThickness,
                    height: max(0, frame.height - size)
                ))
            ]
            return edgeHandles.first { $0.1.contains(point) }?.0
        }

        private func cursor(at point: CGPoint) -> NSCursor {
            if let hit = resizeHit(at: point) {
                return hit.anchor.cursor
            }
            guard let layer = hitLayer(at: point) else { return .arrow }
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                return anchor.cursor
            }
            return layer.isEditable ? .openHand : .arrow
        }

        private func setHoveredLayer(_ id: String?) {
            guard hoveredLayerID != id else { return }
            hoveredLayerID = id
            onHover?(id)
        }
    }
}
