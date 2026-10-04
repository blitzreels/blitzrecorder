import AppKit
import SwiftUI

private struct BlitzWindowToolbarModifier: ViewModifier {
    @EnvironmentObject private var updates: AppUpdateController
    @Environment(\.workspaceRecorder) private var recorder
    let showsUpdate: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.leading, MainWindowChrome.toolbarLeadingInset)
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
                GlobalExportStatusBar(vm: recorder)
                GlobalVideoImportStatusBar(vm: recorder)
            }
            if showsUpdate, updates.updateVersion != nil {
                AppUpdateBanner()
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
    func blitzWindowToolbar(showsUpdate: Bool) -> some View {
        modifier(BlitzWindowToolbarModifier(showsUpdate: showsUpdate))
    }
}

private struct WorkspaceRecorderKey: EnvironmentKey {
    static let defaultValue: RecorderViewModel? = nil
}

extension EnvironmentValues {
    var workspaceRecorder: RecorderViewModel? {
        get { self[WorkspaceRecorderKey.self] }
        set { self[WorkspaceRecorderKey.self] = newValue }
    }
}

private struct GlobalExportStatusBar: View {
    @Bindable var vm: RecorderViewModel

    private var projectTitle: String {
        vm.recentProjects.first { $0.projectPath == vm.activeExportProjectURL?.path }?.displayTitle ?? "video"
    }

    var body: some View {
        if vm.isExporting || vm.lastExportSucceededURL != nil || vm.lastExportError != nil {
            HStack(spacing: 12) {
                if vm.isExporting {
                    Text("Exporting \(projectTitle)")
                        .lineLimit(1)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(BlitzUI.mint)
                        .frame(minWidth: 80, maxWidth: 220)
                    Text("\(Int((progress * 100).rounded()))%")
                        .monospacedDigit()
                    Spacer(minLength: 0)
                } else {
                    Image(systemName: vm.lastExportError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(vm.lastExportError == nil ? BlitzUI.mint : BlitzUI.warning)
                    Text(vm.lastExportError.map { "Export failed: " + $0 } ?? savedTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let url = vm.lastExportSucceededURL {
                        if vm.isEditorVisible {
                            Button("Share link", systemImage: "link") { vm.exportFollowUp = .share(url) }
                                .blitzButton(.secondary)
                                .help("Upload this export and copy a watch link")
                            Button("Send to BlitzReels", systemImage: "paperplane") { vm.exportFollowUp = .sendToBlitzReels(url) }
                                .blitzButton(.secondary)
                                .help("Open this export in the BlitzReels panel")
                        }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(vm.variantExportURLs.count > 1 ? vm.variantExportURLs : [url])
                        }
                        .blitzButton(.secondary)
                        .help(url.path)
                    }
                    Button {
                        vm.lastExportSucceededURL = nil
                        vm.lastExportError = nil
                        vm.variantExportURLs = []
                    } label: { Image(systemName: "xmark") }
                        .blitzButton(.quiet)
                        .accessibilityLabel("Dismiss export status")
                }
            }
            .font(BlitzType.caption)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(BlitzUI.panelBackground)
        }
    }

    private var savedTitle: String {
        vm.variantExportURLs.count > 1
            ? "Saved \(vm.variantExportURLs.count) videos"
            : "Saved \(vm.lastExportSucceededURL?.lastPathComponent ?? "video")"
    }

    private var progress: Double {
        guard vm.isExportingVariants else { return vm.exportProgress }
        return (Double(max(0, vm.variantExportIndex - 1)) + vm.exportProgress) / Double(max(1, vm.variantExportTotal))
    }
}
