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
    }
    let configuration: Configuration
    @State private var draft: EditorPlacedItem.Timing?

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
        case .zoom: .purple
        case .music: .pink
        }
    }

    var body: some View {
        ZStack {
            if item.isPoint {
                Image(systemName: "diamond.fill").font(.system(size: 13))
                    .foregroundStyle(configuration.isSelected ? BlitzUI.mint : tint)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(configuration.isSelected ? 0.3 : 0.15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(configuration.isSelected ? BlitzUI.mint : tint.opacity(0.6),
                                          lineWidth: configuration.isSelected ? 2 : 1)
                    }
                HStack(spacing: 5) {
                    Image(systemName: item.symbol)
                    Text(item.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 10)
                .clipped()
            }
        }
        .frame(width: width, height: configuration.height)
        .contentShape(.rect)
        .onTapGesture { configuration.select(item.id) }
        .gesture(drag(.move), isEnabled: configuration.isInteractive && item.canChangeTiming)
        .overlay {
            if configuration.isSelected, item.canChangeTiming, !item.isPoint, width >= 24 {
                HStack {
                    handle(.trimStart)
                    Spacer(minLength: 0)
                    handle(.trimEnd)
                }
            }
        }
        .opacity(item.isEnabled ? 1 : 0.4)
        .offset(x: start - (item.isPoint ? 8 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.id.kind == .zoom ? "Zoom point" : item.id.kind == .mask ? "Privacy mask" : item.id.kind == .music ? "Music" : "Text") · \(item.title)")
        .accessibilityValue("\(EditorPlaybackPosition.display(timing.start))–\(EditorPlaybackPosition.display(timing.end))\(configuration.isSelected ? ", Selected" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { configuration.select(item.id) }
        .help(!item.canChangeTiming ? "Loops throughout the export. Select to change music or volume."
              : item.isPoint ? "Drag to move this zoom point. Delete removes it."
              : "Drag to move. Select and drag either edge to change duration. Delete removes this item.")
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3") { configuration.select(item.id) }
            Button("Remove", systemImage: "trash", role: .destructive) { configuration.remove(item.id) }
        }
        .disabled(!configuration.isInteractive)
    }

    private func handle(_ gesture: EditorPlacedItemEditing.Gesture) -> some View {
        Capsule().fill(BlitzUI.mint).frame(width: 3, height: 16)
            .frame(width: 12, height: configuration.height)
            .contentShape(.rect)
            .highPriorityGesture(drag(gesture), isEnabled: configuration.isInteractive)
    }

    private func drag(_ gesture: EditorPlacedItemEditing.Gesture) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if draft == nil { configuration.select(item.id) }
                draft = EditorPlacedItemEditing.timing(.init(item: item,
                    delta: Double(value.translation.width / configuration.pixelsPerSecond), gesture: gesture,
                    projection: configuration.projection))
            }
            .onEnded { _ in
                if let draft, draft != item.timing {
                    configuration.change(.init(id: item.id, timing: draft))
                }
                draft = nil
            }
    }
}
