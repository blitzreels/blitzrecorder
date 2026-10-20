import SwiftUI

/// Whether BlitzRecorder's own windows and controls show up in the recording, and what that means for screen shares.
enum RecorderVisibility {
    static func symbol(hidden: Bool) -> String { hidden ? BlitzSymbols.recorderHidden : BlitzSymbols.recorderShown }

    static func title(hidden: Bool) -> String { hidden ? "Hidden" : "Visible" }

    static func help(hidden: Bool) -> String {
        hidden
            ? "BlitzRecorder is hidden from this recording. To keep it out of a call too, share a window instead of your whole screen."
            : "BlitzRecorder appears in this recording and in screen shares."
    }
}

/// Studio toolbar control: shows whether BlitzRecorder is recorded and lets the person switch before recording.
struct RecorderVisibilityMenu: View {
    @Bindable var vm: RecorderViewModel

    private var hidden: Bool { !vm.settings.includesRecorderUI }

    var body: some View {
        BlitzGlassMenu(entries: entries, menuWidth: 280) {
            HStack(spacing: 7) {
                BlitzSymbol(configuration: .init(name: RecorderVisibility.symbol(hidden: hidden), size: 16))
                    .foregroundStyle(hidden ? BlitzUI.secondaryText : BlitzUI.warning)
                Text(RecorderVisibility.title(hidden: hidden))
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.primaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: BlitzControlMetrics.toolbarHeight)
        }
        .disabled(vm.state != .idle)
        .help(RecorderVisibility.help(hidden: hidden))
        .accessibilityLabel("BlitzRecorder \(RecorderVisibility.title(hidden: hidden).lowercased()) in recordings")
    }

    private var entries: [BlitzMenuEntry] {
        [
            .item(.init(title: "Hide BlitzRecorder",
                        subtitle: "Keep its windows and controls out of the video and of calls that allow it",
                        systemImage: BlitzSymbols.recorderHidden, isSelected: hidden,
                        action: { vm.setRecorderUIIncluded(false) })),
            .item(.init(title: "Show BlitzRecorder", subtitle: "Record BlitzRecorder itself, for a tutorial",
                        systemImage: BlitzSymbols.recorderShown, isSelected: !hidden,
                        action: { vm.setRecorderUIIncluded(true) }))
        ]
    }
}

/// Recording controls: says whether the controls themselves are being recorded.
struct RecorderVisibilityIndicator: View {
    let hidden: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: RecorderVisibility.symbol(hidden: hidden))
                .font(BlitzType.glyph(11))
            Text(RecorderVisibility.title(hidden: hidden))
                .font(BlitzType.captionEmphasis)
        }
        .foregroundStyle(hidden ? BlitzUI.secondaryText : BlitzUI.warning)
        .fixedSize()
        .help(RecorderVisibility.help(hidden: hidden))
        .accessibilityLabel("BlitzRecorder \(RecorderVisibility.title(hidden: hidden).lowercased()) in this recording")
    }
}
