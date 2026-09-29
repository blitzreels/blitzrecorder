import SwiftUI

struct EditorToolbar: View {
    @Bindable var vm: RecorderViewModel
    var title: String
    var onFillWindow: () -> Void
    var onSelectOutputLayout: (CaptureLayout) -> Void
    var exportButton: AnyView

    var body: some View {
        HStack(spacing: 0) {
            Button("Projects", action: vm.showProjects)
                .blitzButton(.quiet)
                .controlSize(.small)
                .help("Open projects")
            Text("/")
                .foregroundStyle(BlitzUI.secondaryText)
                .padding(.horizontal, 8)

            Text(title)
                .font(BlitzType.headline)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .allowsWindowActivationEvents(true)
                .onTapGesture(count: 2, perform: onFillWindow)

            Spacer(minLength: 12)
            ViewThatFits(in: .horizontal) {
                formatPicker { $0.formatTitle }
                formatPicker { $0.shortLabel }
            }
            .controlSize(.small)
            .help("Choose the output aspect ratio")
            .disabled(vm.state != .idle)
            Spacer(minLength: 12)
                .contentShape(.rect)
                .allowsWindowActivationEvents(true)
                .onTapGesture(count: 2, perform: onFillWindow)

            exportButton
        }
    }

    private func formatPicker(label: @escaping (CaptureLayout) -> String) -> some View {
        BlitzSegmentedPicker(configuration: .init(title: "Aspect ratio", options: CaptureLayout.allCases, selection: Binding(
            get: { vm.lastExportedProject?.selectedOutputLayout ?? .horizontal },
            set: onSelectOutputLayout
        ), label: label, symbolName: { $0.symbolName }))
        .fixedSize()
    }
}

extension CaptureLayout {
    var formatTitle: String {
        switch self {
        case .vertical: "Vertical · 9:16"
        case .horizontal: "Landscape · 16:9"
        case .square: "Square · 1:1"
        }
    }
}
