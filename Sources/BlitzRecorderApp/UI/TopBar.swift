import SwiftUI

struct RecordingOutputPicker: View {
    @Bindable var vm: RecorderViewModel
    @State private var hoveredLayout: CaptureLayout?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(CaptureLayout.allCases, id: \.self) { layout in
                    layoutButton(layout)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .blitzGlassSurface(cornerRadius: 15)
        .help("Recording output aspect ratio")
    }

    private func layoutButton(_ layout: CaptureLayout) -> some View {
        let isSelected = vm.settings.layout == layout
        let isHovered = hoveredLayout == layout
        return Button {
            vm.setLayout(layout)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: layout.symbolName)
                    .font(.system(size: 12, weight: .bold))
                Text(layout.shortLabel)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.72))
            .frame(width: 66, height: 27)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(buttonBackground(isSelected: isSelected, isHovered: isHovered))
        )
        .disabled(vm.state != .idle)
        .opacity(vm.state == .idle || isSelected ? 1 : 0.45)
        .onHover { hovering in
            hoveredLayout = hovering ? layout : (hoveredLayout == layout ? nil : hoveredLayout)
        }
        .pointingHandCursor()
        .help("\(layout.titleLabel) \(layout.shortLabel)")
    }

    private func buttonBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.white
        }
        if isHovered {
            return Color.white.opacity(0.12)
        }
        return Color.clear
    }
}
