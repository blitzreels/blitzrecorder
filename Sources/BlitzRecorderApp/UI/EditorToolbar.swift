import SwiftUI

struct EditorToolbar: View {
    @Bindable var vm: RecorderViewModel
    var title: String
    @Binding var showsInspector: Bool
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .allowsWindowActivationEvents(true)
                .onTapGesture(count: 2, perform: onFillWindow)

            Spacer(minLength: 12)
            BlitzSegmentedPicker(configuration: .init(title: "Aspect ratio", options: CaptureLayout.allCases, selection: Binding(
                get: { vm.lastExportedProject?.selectedOutputLayout ?? .horizontal },
                set: onSelectOutputLayout
            ), label: { $0.shortLabel }, symbolName: { $0.symbolName }))
            .controlSize(.small)
            .fixedSize()
            .help("Choose the output aspect ratio")
            .disabled(vm.state != .idle)
            Spacer(minLength: 12)
                .contentShape(.rect)
                .allowsWindowActivationEvents(true)
                .onTapGesture(count: 2, perform: onFillWindow)

            BlitzToolbarButton(configuration: .init(
                title: showsInspector ? "Hide inspector" : "Show inspector",
                symbolName: "sidebar.right",
                showsTitle: false,
                action: { showsInspector.toggle() }
            ))
            .accessibilityValue(showsInspector ? "Visible" : "Hidden")
            .help(showsInspector ? "Hide editing tools to enlarge the preview" : "Show editing tools")
            .padding(.trailing, 12)

            exportButton
        }
    }
}
