import AppKit
import SwiftUI

private struct BlitzWindowToolbarModifier: ViewModifier {
    @Environment(\.workspaceRecorder) private var recorder
    @Environment(\.windowToolbarLeadingInset) private var leadingInset

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.leading, leadingInset)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity)
                .frame(height: MainWindowChrome.toolbarHeight)
                .background {
                    BlitzUI.panelBackground
                        .contentShape(.rect)
                        .gesture(WindowDragGesture())
                        .allowsWindowActivationEvents(true)
                }

            if let recorder {
                GlobalExportProgressBar(vm: recorder)
                GlobalVideoImportStatusBar(vm: recorder)
            }
        }
        .zIndex(1)
    }
}

private struct GlobalVideoImportStatusBar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        if vm.videoImportProgress != nil || vm.videoImportError != nil {
            HStack(spacing: 12) {
                if let progress = vm.videoImportProgress {
                    Text("\(progress.stage) · \(progress.filename)").lineLimit(1)
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(BlitzUI.mint)
                        .frame(minWidth: 80, maxWidth: 220)
                        .accessibilityLabel(progress.stage)
                    if let fraction = progress.fraction {
                        Text("\(Int((fraction * 100).rounded()))%").monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Button("Cancel") { vm.videoImportTask?.cancel() }
                        .blitzButton(.secondary)
                } else if let error = vm.videoImportError {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(BlitzUI.warning)
                    Text("Import failed: \(error)").lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Try again", action: vm.chooseVideoToImport).blitzButton(.secondary)
                    Button { vm.videoImportError = nil } label: { Image(systemName: "xmark") }
                        .blitzButton(.quiet)
                        .accessibilityLabel("Dismiss import error")
                }
            }
            .font(BlitzType.caption)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(BlitzUI.panelBackground)
        }
    }
}

extension View {
    func blitzWindowToolbar() -> some View {
        modifier(BlitzWindowToolbarModifier())
    }
}

private struct WorkspaceRecorderKey: EnvironmentKey {
    static let defaultValue: RecorderViewModel? = nil
}

private struct WindowToolbarLeadingInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = MainWindowChrome.trafficLightsWidth
}

extension EnvironmentValues {
    var workspaceRecorder: RecorderViewModel? {
        get { self[WorkspaceRecorderKey.self] }
        set { self[WorkspaceRecorderKey.self] = newValue }
    }

    var windowToolbarLeadingInset: CGFloat {
        get { self[WindowToolbarLeadingInsetKey.self] }
        set { self[WindowToolbarLeadingInsetKey.self] = newValue }
    }
}

private struct GlobalExportProgressBar: View {
    @Bindable var vm: RecorderViewModel

    private var projectTitle: String {
        vm.recentProjects.first { $0.projectPath == vm.activeExportProjectURL?.path }?.displayTitle ?? "video"
    }

    private var progress: Double {
        guard vm.isExportingVariants else { return vm.exportProgress }
        return (Double(max(0, vm.variantExportIndex - 1)) + vm.exportProgress) / Double(max(1, vm.variantExportTotal))
    }

    var body: some View {
        if vm.isExporting {
            HStack(spacing: 12) {
                Text("Exporting \(projectTitle)")
                    .lineLimit(1)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.mint)
                    .frame(minWidth: 80, maxWidth: 220)
                Text("\(Int((progress * 100).rounded()))%")
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .font(BlitzType.caption)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(BlitzUI.panelBackground)
        }
    }
}
