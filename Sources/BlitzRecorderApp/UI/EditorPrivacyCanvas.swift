import AppKit
import SwiftUI

struct EditorPrivacyCanvas: NSViewRepresentable {
    struct Configuration {
        let session: PrivacyEditingSession
        let scene: RecordingScene
        let renderSize: CGSize
        let aspectRatios: [SceneLayerKind: CGFloat]
        let hiddenKinds: Set<SceneLayerKind>
        let masks: [PrivacyMask]
        let selectedID: UUID?
        let drawingSource: SceneLayerKind?
    }

    let configuration: Configuration

    func makeNSView(context: Context) -> PrivacyCanvasView {
        let view = PrivacyCanvasView()
        view.configuration = configuration
        return view
    }

    func updateNSView(_ view: PrivacyCanvasView, context: Context) {
        view.configuration = configuration
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

@MainActor
final class PrivacyCanvasView: NSView {
    var configuration: EditorPrivacyCanvas.Configuration?
    private struct Drag {
        let original: PrivacyMask
        let start: CGPoint
        let source: PrivacyCanvasSource
        let gesture: PrivacyCanvasGeometry.Gesture
    }
    private var drag: Drag?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var sources: [PrivacyCanvasSource] {
        guard let configuration else { return [] }
        return PrivacyCanvasGeometry.sources(.init(size: bounds.size, renderSize: configuration.renderSize,
            scene: configuration.scene, aspectRatios: configuration.aspectRatios, hiddenKinds: configuration.hiddenKinds))
    }

    override func resetCursorRects() {
        guard let configuration else { return }
        if let source = sources.first(where: { $0.kind == configuration.drawingSource }) {
            addCursorRect(source.visibleFrame, cursor: .crosshair)
        } else {
            for mask in configuration.masks {
                guard let source = sources.first(where: { $0.kind == mask.source }) else { continue }
                let frame = source.displayedFrame(mask).intersection(source.visibleFrame)
                if !frame.isNull, !frame.isEmpty { addCursorRect(frame, cursor: .openHand) }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let configuration else { return }
        for mask in configuration.masks {
            guard let source = sources.first(where: { $0.kind == mask.source }), mask.frame.width > 0 else { continue }
            let frame = source.displayedFrame(mask).intersection(source.visibleFrame)
            guard !frame.isNull, !frame.isEmpty else { continue }
            let selected = configuration.selectedID == mask.id
            (selected ? NSColor.systemMint : NSColor.white.withAlphaComponent(0.45)).setStroke()
            let border = NSBezierPath(rect: frame)
            border.lineWidth = selected ? 2 : 1
            border.stroke()
            if selected {
                for handle in handles(frame) {
                    NSColor.systemMint.setFill()
                    NSBezierPath(roundedRect: CGRect(x: handle.point.x - 4, y: handle.point.y - 4, width: 8, height: 8),
                                 xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let configuration else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let kind = configuration.drawingSource,
           let source = sources.last(where: { $0.kind == kind && $0.visibleFrame.contains(point) }),
           let mask = configuration.session.selected {
            drag = .init(original: mask, start: source.pointInSource(point), source: source, gesture: .draw)
            return
        }
        let ordered = configuration.masks.sorted { $0.id == configuration.selectedID && $1.id != configuration.selectedID }
        for mask in ordered {
            guard let source = sources.last(where: { $0.kind == mask.source }) else { continue }
            let frame = source.displayedFrame(mask).intersection(source.visibleFrame)
            guard !frame.isNull, !frame.isEmpty else { continue }
            if mask.id == configuration.selectedID,
               let handle = handles(frame).first(where: { hypot($0.point.x - point.x, $0.point.y - point.y) <= 10 }) {
                configuration.session.select(mask.id)
                drag = .init(original: mask, start: source.pointInSource(point), source: source, gesture: .resize(handle.anchor))
                return
            }
            if frame.contains(point) {
                configuration.session.select(mask.id)
                drag = .init(original: mask, start: source.pointInSource(point), source: source, gesture: .move)
                return
            }
        }
        configuration.session.select(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let configuration else { return }
        var mask = drag.original
        let point = convert(event.locationInWindow, from: nil)
        mask.frame = PrivacyCanvasGeometry.changedFrame(.init(frame: mask.frame, start: drag.start,
            current: drag.source.pointInSource(point), gesture: drag.gesture))
        configuration.session.preview(mask)
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag, let configuration else { return }
        defer { self.drag = nil }
        var mask = drag.original
        mask.frame = PrivacyCanvasGeometry.changedFrame(.init(frame: mask.frame, start: drag.start,
            current: drag.source.pointInSource(convert(event.locationInWindow, from: nil)), gesture: drag.gesture))
        if mask.frame == drag.original.frame, !configuration.session.isDrawing { return }
        configuration.session.commit(mask)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            drag = nil
            configuration?.session.cancelGesture()
        } else { super.keyDown(with: event) }
    }

    private struct Handle { let point: CGPoint; let anchor: ResizeAnchor }
    private func handles(_ frame: CGRect) -> [Handle] {
        [.init(point: .init(x: frame.minX, y: frame.minY), anchor: .topLeft),
         .init(point: .init(x: frame.maxX, y: frame.minY), anchor: .topRight),
         .init(point: .init(x: frame.minX, y: frame.maxY), anchor: .bottomLeft),
         .init(point: .init(x: frame.maxX, y: frame.maxY), anchor: .bottomRight)]
    }
}
