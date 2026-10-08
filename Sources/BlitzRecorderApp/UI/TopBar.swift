import SwiftUI

struct RecordingOutputPicker: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        BlitzSegmentedPicker(configuration: .init(
            title: "Recording output aspect ratio",
            options: CaptureLayout.allCases,
            selection: Binding(get: { vm.settings.layout }, set: { vm.setLayout($0) }),
            label: { $0.formatTitle },
            symbolName: { $0.symbolName },
            help: { "Record \($0.shortLabel) video" }
        ))
        .fixedSize()
        .disabled(vm.state != .idle)
    }
}
