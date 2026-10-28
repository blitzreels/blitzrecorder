import SwiftUI

/// Whether BlitzRecorder's own windows and controls show up in the recording, and what that means for screen shares.
enum RecorderVisibility {
    static func symbol(hidden: Bool) -> String { hidden ? BlitzSymbols.recorderHidden : BlitzSymbols.recorderShown }

    static func title(hidden: Bool) -> String { hidden ? "App hidden" : "App visible" }

    static func help(hidden: Bool) -> String {
        hidden
            ? "BlitzRecorder is hidden from this recording. To keep it out of a call too, share a window instead of your whole screen."
            : "BlitzRecorder appears in this recording and in screen shares."
    }
}

/// Studio toolbar control: whether BlitzRecorder itself shows in the recording. Quiet while hidden (the usual
/// case), amber while it would be recorded.
struct RecorderVisibilityMenu: View {
    @Bindable var vm: RecorderViewModel
    @State private var isPresented = false

    private var hidden: Bool { !vm.settings.includesRecorderUI }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            StudioToolbarIcon(name: RecorderVisibility.symbol(hidden: hidden),
                              color: hidden ? BlitzUI.secondaryText : BlitzUI.warning)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented, variant: .borderless))
        .disabled(vm.state != .idle)
        .help(RecorderVisibility.help(hidden: hidden))
        .accessibilityLabel(hidden ? "BlitzRecorder hidden from recordings" : "BlitzRecorder shown in recordings")
        .onChange(of: vm.state) { if vm.state != .idle { isPresented = false } }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BlitzMenuList(entries: entries, width: 300, maxHeight: BlitzMenuList.adaptiveMaxHeight) {
                isPresented = false
            }
        }
    }

    private var entries: [BlitzMenuEntry] {
        [
            .section("BlitzRecorder in the video"),
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
        .accessibilityLabel(hidden ? "BlitzRecorder hidden from this recording" : "BlitzRecorder shown in this recording")
    }
}
