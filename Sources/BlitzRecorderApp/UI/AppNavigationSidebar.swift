import SwiftUI

struct AppNavigationSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(spacing: 8) {
            navigationItem(.init(title: "Projects", symbol: "folder",
                selected: vm.studioMode == .projects && !vm.isShowingSettings,
                detail: nil, enabled: vm.canShowProjects, action: vm.showProjects))
            navigationItem(.init(title: "Record", symbol: "record.circle",
                selected: vm.studioMode == .record && !vm.isShowingSettings,
                detail: recordingDetail, enabled: !vm.projectTrash.isWorking, action: vm.showRecorder))

            if vm.canOpenEditor {
                navigationItem(.init(title: "Resume editing", symbol: "scissors",
                    selected: vm.isEditorVisible, detail: vm.lastExportedProject?.title,
                    enabled: vm.state == .idle && !vm.projectTrash.isWorking, action: vm.openEditor))
            }

            Spacer(minLength: 16)

            navigationItem(.init(title: "Settings", symbol: "gearshape",
                selected: vm.isShowingSettings, detail: "⌘,", enabled: true,
                action: { vm.showSettings(nil) }))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .padding(.top, MainWindowChrome.toolbarHeight)
        .frame(width: MainWindowChrome.navigationWidth)
        .frame(maxHeight: .infinity)
        .background(BlitzUI.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App navigation")
    }

    private struct Item {
        let title: String
        let symbol: String
        let selected: Bool
        let detail: String?
        let enabled: Bool
        let action: () -> Void

        var help: String { detail.map { "\(title) · \($0)" } ?? title }
    }

    private func navigationItem(_ item: Item) -> some View {
        Button(action: item.action) {
            Image(systemName: item.symbol)
                .font(BlitzType.symbol(17))
                .symbolVariant(item.selected ? .fill : .none)
                .foregroundStyle(item.selected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                .frame(width: 24, height: 32)
                .overlay(alignment: .topTrailing) {
                    if item.symbol == "record.circle", vm.state != .idle {
                        Circle().fill(vm.state == .recording ? BlitzUI.recordRed : BlitzUI.warning)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(BlitzUI.panelBackground, lineWidth: 2))
                            .offset(x: 2, y: 1)
                    }
                }
        }
        .blitzButton(item.selected ? .secondary : .quiet)
        .controlSize(.small)
        .disabled(!item.enabled)
        .accessibilityAddTraits(item.selected ? [.isSelected] : [])
        .accessibilityLabel(item.title)
        .accessibilityValue(item.detail ?? "")
        .help(item.help)
    }

    private var recordingDetail: String? {
        switch vm.state {
        case .idle: nil
        case .recording: "Recording · \(vm.formattedElapsed)"
        case .paused: "Paused · \(vm.formattedElapsed)"
        case .starting: "Starting…"
        case .finishing: "Saving…"
        }
    }
}
