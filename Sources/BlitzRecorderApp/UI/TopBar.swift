import SwiftUI

struct RecordingOutputPicker: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CaptureLayout.allCases, id: \.self) { layout in
                BlitzTab(configuration: .init(
                    title: layout.formatTitle,
                    symbolName: layout.symbolName,
                    isSelected: vm.settings.layout == layout,
                    expands: false,
                    action: { vm.setLayout(layout) }
                ))
                .help("Record \(layout.shortLabel) video")
            }
        }
        .blitzTabGroup()
        .disabled(vm.state != .idle)
        .help("Recording output aspect ratio")
    }
}
