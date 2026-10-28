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
                        .simultaneousGesture(TapGesture(count: 2).onEnded { TitlebarDoubleClick.performSystemAction() })
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

    /// The library shows an import as a row where the project will land, so the bar only follows other pages.
    private var progress: VideoProjectImporter.Progress? {
        let showsImportRow = vm.studioMode == .projects && !vm.isShowingSettings
            && vm.projectLibraryNavigation.section == .recordings
        return showsImportRow ? nil : vm.libraryActions.videoImportProgress
    }

    var body: some View {
        if progress != nil || vm.libraryActions.videoImportError != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let progress {
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

/// AppKit zooms a window on any double-click in its title bar, even one on a toolbar button. Double-clicks in the
/// toolbar band reach controls as single clicks instead, and only the toolbar's empty background runs the
/// system's double-click action (zoom or minimize, from System Settings → Desktop & Dock).
@MainActor
enum TitlebarDoubleClick {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            guard event.clickCount >= 2, let window = event.window,
                  window.styleMask.contains(.titled), window.styleMask.contains(.fullSizeContentView),
                  let contentView = window.contentView else { return event }
            let point = contentView.convert(event.locationInWindow, from: nil)
            let distanceFromTop = contentView.isFlipped ? point.y : contentView.bounds.height - point.y
            guard distanceFromTop <= MainWindowChrome.toolbarHeight else { return event }
            if let hit = contentView.hitTest(point), hit is NSText || hit is NSTextField { return event }
            return NSEvent.mouseEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                eventNumber: event.eventNumber,
                clickCount: 1,
                pressure: event.pressure
            ) ?? event
        }
    }

    static func performSystemAction() {
        guard let window = NSApp.keyWindow else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}
