import SwiftUI

struct EditorShortcutHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BlitzUI.sectionLabel("Timeline shortcuts", icon: "keyboard")
            VStack(spacing: 8) {
                row(.init(title: "Play / pause", keys: "Space"))
                row(.init(title: "Back 3 seconds · pause · play faster", keys: "J  K  L"))
                row(.init(title: "Previous / next frame", keys: "←  →"))
                row(.init(title: "Back / forward 1 second", keys: "⇧ ←  ⇧ →"))
                row(.init(title: "Previous / next scene", keys: "↑  ↓"))
                row(.init(title: "Start / end of recording", keys: "Home  End"))
            }
            Divider()
            VStack(spacing: 8) {
                row(.init(title: "Select a time range", keys: "Drag a track"))
                row(.init(title: "Set range start / end", keys: "I  O"))
                row(.init(title: "Clear selection", keys: "Esc"))
                row(.init(title: "Cut selected range / join selected scene", keys: "Delete"))
                row(.init(title: "Restore removed footage in range", keys: "⇧ Delete"))
                row(.init(title: "Split scene at playhead", keys: "⌘ B / S"))
                row(.init(title: "Toggle selected track", keys: "M / H"))
                row(.init(title: "Undo / redo", keys: "⌘ Z  /  ⇧ ⌘ Z"))
            }
            Divider()
            VStack(spacing: 8) {
                row(.init(title: "Zoom out / in", keys: "−  +"))
                row(.init(title: "Fit recording", keys: "F"))
                row(.init(title: "Show shortcuts", keys: "?"))
            }
            Text("Drag the ruler to scrub. Range cuts apply to all tracks and can be undone.")
                .font(.system(size: 11))
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440)
        .background(BlitzUI.panelBackground)
    }

    private struct Row {
        let title: String
        let keys: String
    }

    private func row(_ row: Row) -> some View {
        HStack(spacing: 16) {
            Text(row.title)
                .foregroundStyle(BlitzUI.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(BlitzUI.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .blitzCard(cornerRadius: BlitzUI.controlRadius)
        }
        .font(.system(size: 11))
    }
}
