import AppKit
import SwiftUI

struct EditorPlacedItemClip: View {
    struct Configuration {
        let item: EditorPlacedItem
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let height: CGFloat
        let isSelected: Bool
        let isInteractive: Bool
        let select: (EditorPlacedItem.ID) -> Void
        let change: (EditorPlacedItemEditing.Change) -> Void
        let remove: (EditorPlacedItem.ID) -> Void
        let snapTargets: (EditorPlacedItem.ID) -> EditorTimelineSnapTargets
        let showSnapGuide: (Double?) -> Void
    }
    private struct DragOrigin {
        let item: EditorPlacedItem
        let gesture: EditorPlacedItemEditing.Gesture
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let targets: EditorTimelineSnapTargets
    }
    let configuration: Configuration
    @State private var dragOrigin: DragOrigin?
    @State private var snappedTime: Double?
    @State private var draft: EditorPlacedItem.Timing?
    @State private var isHovering = false
    @State private var hoveredHandle: EditorPlacedItemEditing.Gesture?

    private var item: EditorPlacedItem { configuration.item }
    private var timing: EditorPlacedItem.Timing { draft ?? item.timing }
    private var start: CGFloat { CGFloat(configuration.projection.displayTime(timing.start)) * configuration.pixelsPerSecond }
    private var width: CGFloat {
        item.isPoint ? 16 : max(8, CGFloat(configuration.projection.displayTime(timing.end)
            - configuration.projection.displayTime(timing.start)) * configuration.pixelsPerSecond)
    }
    private var tint: Color {
        switch item.id.kind {
        case .mask: .orange
        case .text: .cyan
        case .caption: .cyan
        case .zoom: .purple
        case .music: .pink
        }
    }

    var body: some View {
        ZStack {
            if item.isPoint {
                Image(systemName: "diamond.fill").font(BlitzType.glyph(13))
                    .foregroundStyle(configuration.isSelected || isHovering ? BlitzUI.accent : tint)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(configuration.isSelected || isHovering ? 0.3 : 0.15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(configuration.isSelected ? BlitzUI.accent : tint.opacity(isHovering ? 1 : 0.6),
                                          lineWidth: configuration.isSelected || isHovering ? 2 : 1)
                    }
                HStack(spacing: 5) {
                    Image(systemName: item.symbol)
                    Text(item.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(BlitzType.footnote)
                .padding(.horizontal, 10)
                .clipped()
            }
        }
        .frame(width: width, height: configuration.height)
        .contentShape(.rect)
        .blitzCursor(item.canChangeTiming ? (draft == nil ? .openHand : .closedHand) : .arrow)
        .onHover { isHovering = $0 && configuration.isInteractive }
        .onTapGesture { configuration.select(item.id) }
        .gesture(drag(.move), isEnabled: configuration.isInteractive && item.canChangeTiming)
        .overlay {
            if configuration.isSelected, item.canChangeTiming, !item.isPoint {
                HStack {
                    handle(.trimStart)
                    Spacer(minLength: 0)
                    handle(.trimEnd)
                }
                .frame(width: max(36, width))
            }
        }
        .zIndex(configuration.isSelected ? 10 : 0)
        .opacity(item.isEnabled ? 1 : 0.4)
        .offset(x: start - (item.isPoint ? 8 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.id.kind == .zoom ? "Zoom point" : item.id.kind == .mask ? "Privacy mask" : item.id.kind == .music ? "Music" : "Text") · \(item.title)")
        .accessibilityValue("\(EditorPlaybackPosition.display(timing.start))–\(EditorPlaybackPosition.display(timing.end))\(configuration.isSelected ? ", Selected" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { configuration.select(item.id) }
        .help(!item.canChangeTiming ? "Loops throughout the export. Select to change music or volume."
              : item.isPoint ? "Drag to move this zoom point. It sticks to cuts, sentences and the playhead. "
                + "Hold ⌘ to place it freely. Delete removes it."
              : "\(item.title)\nDrag to move. Select and drag either edge to change duration. "
                + "Edges stick to cuts, scenes, sentences, other items and the playhead. "
                + "Hold ⌘ to place freely. Delete removes this item.")
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3") { configuration.select(item.id) }
            Button("Remove", systemImage: BlitzSymbols.delete, role: .destructive) { configuration.remove(item.id) }
        }
        .disabled(!configuration.isInteractive)
        .onDisappear { updateSnap(nil) }
    }

    private func handle(_ gesture: EditorPlacedItemEditing.Gesture) -> some View {
        EditorTimelineGrip(tint: BlitzUI.accent, isActive: hoveredHandle == gesture)
            .frame(width: 12, height: configuration.height)
            .contentShape(.rect)
            .blitzCursor(.resizeLeftRight)
            .onHover { hoveredHandle = $0 && configuration.isInteractive ? gesture : nil }
            .highPriorityGesture(drag(gesture), isEnabled: configuration.isInteractive)
            .accessibilityLabel(gesture == .trimStart ? "Item start" : "Item end")
            .timelineControl(id: "placed-\(item.id.kind)-\(item.id.value)-\(gesture == .trimStart ? "start" : "end")")
    }

    private func drag(_ gesture: EditorPlacedItemEditing.Gesture) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = .init(item: item, gesture: gesture, projection: configuration.projection,
                        pixelsPerSecond: max(0.001, configuration.pixelsPerSecond),
                        targets: configuration.snapTargets(item.id))
                    configuration.select(item.id)
                }
                guard let origin = dragOrigin else { return }
                let snaps = !NSEvent.modifierFlags.contains(.command)
                let result = EditorPlacedItemEditing.dragged(.init(item: origin.item,
                    delta: Double(value.translation.width / origin.pixelsPerSecond), gesture: origin.gesture,
                    projection: origin.projection,
                    snap: snaps ? .init(targets: origin.targets,
                        tolerance: Double(EditorTimelineSnapTargets.distance / origin.pixelsPerSecond)) : nil))
                draft = result.timing
                updateSnap(result.snappedTime)
            }
            .onEnded { _ in
                if let draft, let dragOrigin, draft != item.timing {
                    configuration.change(.init(id: item.id, timing: draft, gesture: dragOrigin.gesture))
                }
                draft = nil
                dragOrigin = nil
                updateSnap(nil)
            }
    }

    private func updateSnap(_ time: Double?) {
        guard time != snappedTime else { return }
        snappedTime = time
        configuration.showSnapGuide(time)
        if time != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
