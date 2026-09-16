import SwiftUI

struct EditorToolbar: View {
    @Bindable var vm: RecorderViewModel
    var title: String
    var onFillWindow: () -> Void
    var onSelectOutputLayout: (CaptureLayout) -> Void
    var exportButton: AnyView

    var body: some View {
        HStack(spacing: 0) {
            Button {
                vm.showProjects()
            } label: {
                Label("Projects", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.leading, 9)
                    .padding(.trailing, 11)
                    .frame(height: 40)
                    .contentShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(BlitzPressButtonStyle())
            .pointingHandCursor()
            .help("Return to projects")

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: 18)
                .padding(.leading, 4)
                .padding(.trailing, 16)

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
                title: "Settings",
                symbolName: "gearshape",
                showsTitle: false,
                action: { vm.onPresentSettings?(nil) }
            ))
            .help("Open Settings (Cmd+,)")
            .padding(.trailing, 12)

            exportButton
        }
        .frame(height: 44)
    }
}
