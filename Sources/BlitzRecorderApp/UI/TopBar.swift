import SwiftUI

struct TopBar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 8)

            accessButton
            RecordingOutputPicker(vm: vm)
        }
    }

    private var accessButton: some View {
        Button {
            vm.appTab = .creator
        } label: {
            HStack(spacing: 8) {
                Image(systemName: vm.accessController.isPro ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(vm.accessController.isPro ? Color(red: 0.09, green: 1.0, blue: 0.65) : .white.opacity(0.7))
                Text(vm.accessController.isPro ? "Pro" : "\(vm.accessController.freeExportsRemaining) free")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .pointingHandCursor()
        .help("Open plan and access")
    }

}

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
        .glassEffect(.regular, in: .rect(cornerRadius: 15))
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

private struct RecordingStatusBadge: View {
    let state: RecordingState
    let elapsed: String

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: state)
            Text(statusLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(elapsed)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private var statusLabel: String {
        switch state {
        case .starting: return "Starting"
        case .recording: return "REC"
        case .paused: return "Paused"
        case .finishing: return "Saving"
        case .idle: return ""
        }
    }
}

private struct StatusDot: View {
    let state: RecordingState
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing && state == .recording ? 1.25 : 1)
            .animation(state == .recording ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulsing)
            .onAppear { pulsing = true }
    }

    private var color: Color {
        switch state {
        case .idle: return .gray
        case .starting: return Color(red: 0.27, green: 0.7, blue: 1)
        case .recording: return Color(red: 1, green: 0.27, blue: 0.27)
        case .paused: return Color(red: 1, green: 0.7, blue: 0.27)
        case .finishing: return Color(red: 0.27, green: 0.7, blue: 1)
        }
    }
}
