import SwiftUI

struct EditorToolbar: View {
    @Bindable var vm: RecorderViewModel
    var title: ProjectTitlePresentation
    var onFillWindow: () -> Void
    var onSelectOutputLayout: (CaptureLayout) -> Void
    var exportButton: AnyView

    var body: some View {
        BlitzAdaptiveRow(.init(minimumContentWidth: 200)) {
            VStack(alignment: .leading, spacing: 1) {
                if let context = title.context {
                    Text(context)
                        .font(BlitzType.footnote)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(1)
                }
                Text(title.title)
                    .font(BlitzType.headline)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(title.title)
            }
                .truncationMode(.tail)
                .layoutPriority(1)
                .allowsWindowActivationEvents(true)
                .onTapGesture(count: 2, perform: onFillWindow)

            ViewThatFits(in: .horizontal) {
                formatPicker { $0.formatTitle }
                formatPicker { $0.shortLabel }
            }
            .controlSize(.small)
            .help("Choose the output aspect ratio")
            .disabled(vm.state != .idle)

            if vm.onOpenEditorWindow != nil {
                Button(action: vm.openEditorWindow) {
                    Image(systemName: "macwindow.on.rectangle")
                }
                .blitzButton(.quiet)
                .accessibilityLabel("Open Editor Window")
                .help("Move this editor into a separate window")
                .padding(.trailing, 8)
            }
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
