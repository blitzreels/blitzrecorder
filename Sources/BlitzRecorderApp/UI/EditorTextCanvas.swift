import SwiftUI

enum EditorTextFrameEditing {
    enum Handle: CaseIterable { case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight }
    struct Request {
        let frame: CGRect
        let translation: CGSize
        let handle: Handle?
    }

    static func frame(_ request: Request) -> CGRect {
        let frame = request.frame
        let dx = request.translation.width
        let dy = request.translation.height
        guard dx.isFinite, dy.isFinite else { return frame }
        guard let handle = request.handle else {
            return CGRect(x: min(max(0, frame.minX + dx), max(0, 1 - frame.width)),
                y: min(max(0, frame.minY + dy), max(0, 1 - frame.height)), width: frame.width, height: frame.height)
        }
        var left = frame.minX
        var right = frame.maxX
        var top = frame.minY
        var bottom = frame.maxY
        if [.topLeft, .left, .bottomLeft].contains(handle) { left = min(right - 0.04, max(0, left + dx)) }
        if [.topRight, .right, .bottomRight].contains(handle) { right = max(left + 0.04, min(1, right + dx)) }
        if [.topLeft, .top, .topRight].contains(handle) { top = min(bottom - 0.025, max(0, top + dy)) }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) { bottom = max(top + 0.025, min(1, bottom + dy)) }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

struct EditorTextCanvas: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let selection: Binding<EditorSelection?>
        let error: Binding<String?>
    }
    let configuration: Configuration

    private var playback: EditorPlaybackController { configuration.playback }
    private var overlays: [TextOverlay] { playback.edits.textOverlays.filter { $0.isVisible(at: playback.currentTime) } }

    var body: some View {
        GeometryReader { proxy in
            ForEach(overlays) { overlay in
                item(.init(id: .init(kind: .text, value: overlay.id), title: overlay.text, frame: overlay.frame, size: proxy.size))
            }
            if let cue = playback.captionTimeline.cue(at: playback.currentTime),
               let sprite = CaptionRenderer.sprite(.init(.init(cue: cue, track: playback.edits.captions, canvasSize: playback.renderSize))) {
                item(.init(id: .init(kind: .caption, value: cue.id), title: cue.text,
                    frame: playback.edits.captions.frame ?? CGRect(x: sprite.frame.minX / playback.renderSize.width,
                        y: sprite.frame.minY / playback.renderSize.height, width: sprite.frame.width / playback.renderSize.width,
                        height: sprite.frame.height / playback.renderSize.height), size: proxy.size))
            }
        }
    }

    private struct Item {
        let id: EditorPlacedItem.ID
        let title: String
        let frame: CGRect
        let size: CGSize
    }

    private func item(_ item: Item) -> some View {
        EditorTextCanvasItem(configuration: .init(id: item.id, title: item.title, frame: item.frame, size: item.size,
            isSelected: configuration.selection.wrappedValue == .placed(item.id),
            select: {
                playback.pauseForEditing()
                configuration.selection.wrappedValue = .placed(item.id)
            }, change: { change in
                playback.pauseForEditing()
                if change.ended {
                    guard var edits = configuration.vm.editorProject?.edits else { return }
                    if item.id.kind == .text, let index = edits.textOverlays.firstIndex(where: { $0.id == item.id.value }) {
                        edits.textOverlays[index].frame = change.frame
                        if !configuration.vm.applyOutputTextEdits(.init(edits: edits, actionName: "Position Text")) {
                            configuration.error.wrappedValue = "The text position could not be saved."
                        }
                    } else if item.id.kind == .caption, var base = configuration.vm.lastExportedProject?.edits {
                        base.captions.frame = change.frame
                        if !configuration.vm.applyTimelineEdits(.init(edits: base, actionName: "Position Captions")) {
                            configuration.error.wrappedValue = "The caption position could not be saved."
                        }
                    }
                    restorePreview()
                } else {
                    playback.previewTextFrame(.init(id: item.id, frame: change.frame))
                }
            }, cancel: restorePreview))
    }

    private func restorePreview() {
        guard let edits = configuration.vm.editorProject?.edits else { return }
        playback.restoreTextPreview(edits)
    }
}

private struct EditorTextCanvasItem: View {
    struct Change { let frame: CGRect; let ended: Bool }
    struct Configuration {
        let id: EditorPlacedItem.ID
        let title: String
        let frame: CGRect
        let size: CGSize
        let isSelected: Bool
        let select: () -> Void
        let change: (Change) -> Void
        let cancel: () -> Void
    }
    let configuration: Configuration
    @State private var origin: CGRect?
    @State private var startSize: CGSize?
    @State private var draft: CGRect?
    @State private var isHovering = false
    private var frame: CGRect { draft ?? configuration.frame }
    private var size: CGSize { configuration.size }

    var body: some View {
        Rectangle().fill(.clear)
            .overlay { Rectangle().strokeBorder(BlitzUI.accent.opacity(configuration.isSelected ? 1 : isHovering ? 0.6 : 0), lineWidth: 1.5) }
            .frame(width: frame.width * size.width, height: frame.height * size.height)
            .contentShape(.rect)
            .blitzCursor(origin == nil ? .openHand : .closedHand)
            .onHover { isHovering = $0 }
            .onTapGesture(perform: configuration.select)
            .gesture(drag(nil))
            .overlay {
                if configuration.isSelected {
                    ForEach(EditorTextFrameEditing.Handle.allCases, id: \.self) { handle in
                        Rectangle().fill(BlitzUI.accent)
                            .frame(width: 8, height: 8)
                            .padding(5).contentShape(.rect)
                            .blitzCursor(handle == .top || handle == .bottom ? .resizeUpDown : .resizeLeftRight)
                            .highPriorityGesture(drag(handle))
                            .position(point(handle))
                            .accessibilityLabel("Resize text \(String(describing: handle))")
                    }
                }
            }
            .offset(x: frame.minX * size.width, y: frame.minY * size.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Position \(configuration.title)")
            .help("Drag to move text. Drag a handle to resize. Saved for this output format.")
            .onDisappear {
                if origin != nil { configuration.cancel() }
            }
    }

    private func point(_ handle: EditorTextFrameEditing.Handle) -> CGPoint {
        let x: CGFloat = [.topLeft, .left, .bottomLeft].contains(handle) ? 0
            : [.topRight, .right, .bottomRight].contains(handle) ? 1 : 0.5
        let y: CGFloat = [.topLeft, .top, .topRight].contains(handle) ? 0
            : [.bottomLeft, .bottom, .bottomRight].contains(handle) ? 1 : 0.5
        return CGPoint(x: frame.width * size.width * x, y: frame.height * size.height * y)
    }

    private func drag(_ handle: EditorTextFrameEditing.Handle?) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if origin == nil {
                    origin = configuration.frame
                    startSize = size
                    configuration.select()
                }
                guard let origin, let startSize else { return }
                let updated = EditorTextFrameEditing.frame(.init(frame: origin,
                    translation: CGSize(width: value.translation.width / max(1, startSize.width),
                        height: value.translation.height / max(1, startSize.height)), handle: handle))
                draft = updated
                configuration.change(.init(frame: updated, ended: false))
            }
            .onEnded { _ in
                if let draft { configuration.change(.init(frame: draft, ended: true)) }
                origin = nil
                startSize = nil
                draft = nil
            }
    }
}
