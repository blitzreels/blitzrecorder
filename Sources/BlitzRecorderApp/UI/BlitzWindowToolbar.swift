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
                .padding(.vertical, 8)
                .frame(minHeight: MainWindowChrome.toolbarHeight)
                .background {
                    BlitzUI.toolbarBackground
                        .overlay(alignment: .bottom) { BlitzUI.toolbarDivider.frame(height: 1) }
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
        if vm.libraryActions.videoImportProgress != nil || vm.libraryActions.videoImportError != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let progress = vm.libraryActions.videoImportProgress {
                    BlitzAdaptiveRow() {
                        Text("\(progress.stage) · \(progress.filename)")
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(progress.filename)
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                            .tint(BlitzUI.accent)
                            .frame(minWidth: 80, maxWidth: 220)
                            .accessibilityLabel(progress.stage)
                        if let fraction = progress.fraction {
                            Text("\(Int((fraction * 100).rounded()))%").monospacedDigit()
                        }
                        Button("Cancel") { vm.libraryActions.videoImportTask?.cancel() }
                            .blitzButton(.secondary)
                    }
                } else if let error = vm.libraryActions.videoImportError {
                    BlitzAdaptiveRow() {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(BlitzUI.warning)
                            Text("Import failed: \(error)").fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Try again", action: vm.chooseVideoToImport).blitzButton(.secondary)
                        Button { vm.libraryActions.videoImportError = nil } label: { Image(systemName: "xmark") }
                            .blitzButton(.quiet)
                            .accessibilityLabel("Dismiss import error")
                    }
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
        vm.recentProjects.first { $0.projectPath == vm.exports.activeExportProjectURL?.path }?.displayTitle ?? "video"
    }

    private var progress: Double {
        guard vm.exports.isExportingVariants else { return vm.exports.exportProgress }
        return (Double(max(0, vm.exports.variantExportIndex - 1)) + vm.exports.exportProgress) / Double(max(1, vm.exports.variantExportTotal))
    }

    var body: some View {
        if vm.isExporting {
            BlitzAdaptiveRow() {
                Text("Exporting \(projectTitle)")
                    .lineLimit(1)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.accent)
                    .frame(minWidth: 80, maxWidth: 220)
                Text("\(Int((progress * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(BlitzType.caption)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(BlitzUI.panelBackground)
        }
    }
}
