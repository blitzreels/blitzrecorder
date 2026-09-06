import AppKit
import AVFoundation
import Foundation
import SwiftUI

struct BottomDock: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(spacing: 8) {
            if vm.state == .idle {
                if let recovery = vm.lastRecoveryOutput {
                    RecoveryAvailableView(vm: vm, recovery: recovery)
                        .floatingRecordingNotice()
                }
            }

            RecordingActionRow(vm: vm)
        }
        .frame(maxWidth: 720)
        .animation(.easeOut(duration: 0.18), value: vm.state)
        .animation(.easeOut(duration: 0.18), value: vm.canStartRecording)
    }
}

private extension View {
    func floatingRecordingNotice() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(0.78))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }
}

private struct RecordingActionRow: View {
    @Bindable var vm: RecorderViewModel
    var forcesSavedChip = false

    var body: some View {
        HStack(spacing: 8) {
            switch vm.state {
            case .idle:
                RecordButton(vm: vm)

                if let savedURL = savedExportURL {
                    TransportDivider()
                    SavedRecordingChip(
                        vm: vm,
                        url: savedURL,
                        sourceTakeURL: vm.lastExportedSourceTakeURL,
                        warning: vm.lastExportWarning
                    )
                } else if vm.lastPostRecordingProjectOutput != nil {
                    TransportDivider()
                    ProjectReadyChip(vm: vm)
                }
            case .starting:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 40, height: 40)
                SessionStatusText(title: vm.sessionProgressTitle, detail: vm.sessionProgressDetail)
            case .recording, .paused:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        transportStatus
                        screenSwitchButton
                        RecordButton(vm: vm)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            transportStatus
                            RecordButton(vm: vm)
                        }
                        screenSwitchButton
                    }
                }
            case .finishing:
                FinishingProgressStatus(
                    title: vm.sessionProgressTitle,
                    detail: vm.sessionProgressDetail,
                    progress: vm.sessionProgressValue,
                    percent: vm.sessionProgressLabel
                )
            }
        }
        .frame(minHeight: 44)
    }

    private var transportStatus: some View {
        HStack(spacing: 8) {
            PauseButton(vm: vm)
            TransportDivider()
            ElapsedTimeText(isPaused: vm.state == .paused, elapsed: vm.formattedElapsed)
        }
    }

    @ViewBuilder
    private var screenSwitchButton: some View {
        if vm.settings.visibleSources.contains(.screen) {
            DockActionButton(
                title: "Screen",
                systemImage: BlitzSymbols.screen,
                help: "Change the recorded display or window without stopping"
            ) {
                vm.switchRecordedScreenContent()
            }
        }
    }

    private var savedExportURL: URL? {
        if forcesSavedChip { return vm.lastExportedURL }
        guard vm.state == .idle,
              vm.lastRecoveryOutput == nil,
              vm.canStartRecording else { return nil }
        return vm.lastExportedURL
    }
}

private struct TransportDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 2)
    }
}

private struct DockActionButton: View {
    let title: String
    let systemImage: String
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
        .help(help ?? title)
    }
}

private struct ProjectReadyChip: View {
    @Bindable var vm: RecorderViewModel
    @State private var hovering = false

    var body: some View {
        Button {
            vm.openEditor()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlitzUI.mint)
                Text("Edit recording")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.76 : 0.46))
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                BlitzUI.mint.opacity(hovering ? 0.18 : 0.11),
                in: .rect(cornerRadius: BlitzUI.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                    .strokeBorder(BlitzUI.mint.opacity(hovering ? 0.42 : 0.24), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHandCursor()
        .help("Open \(projectDetail) in Edit")
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Open in Edit") { vm.openEditor() }
            Button("Show Source Files") {
                vm.revealLastSourceTracks()
            }
            Divider()
            Button("Clear") { vm.clearPostRecordingStatus() }
        }
    }

    private var projectDetail: String {
        vm.lastPostRecordingProjectOutput?.sourceDirectory.lastPathComponent
            ?? vm.lastExportedSourceTakeURL?.lastPathComponent
            ?? "Editable source project"
    }
}

private struct SavedRecordingChip: View {
    @Bindable var vm: RecorderViewModel
    let url: URL
    let sourceTakeURL: URL?
    let warning: String?
    @State private var metadata = RecordingFileMetadata.empty
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RecordingThumbnailButton(
                image: metadata.thumbnail,
                durationLabel: metadata.durationLabel,
                height: 40,
                help: "Play \(url.lastPathComponent)"
            ) {
                NSWorkspace.shared.open(url)
            }

            SavedRecordingSummaryButton(detail: savedDetail, path: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BlitzUI.warning)
                    .help(warning)
            }

            if sourceTakeURL != nil {
                DockActionButton(title: "Edit", systemImage: "square.and.pencil", help: "Open this take in Edit") {
                    vm.openEditor()
                }
                .fixedSize()
            }

            if hovering {
                DockDismissButton(help: "Clear and get ready for the next take") {
                    vm.clearPostRecordingStatus()
                }
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Play") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Rename…") { vm.renameLastExportedFile() }
            if let sourceTakeURL {
                Button("Open in Edit") { vm.openEditor() }
                Button("Show Source Files") {
                    NSWorkspace.shared.activateFileViewerSelecting([sourceTakeURL])
                }
            }
            Divider()
            Button("Clear") { vm.clearPostRecordingStatus() }
        }
        .task(id: url) {
            metadata = .empty
            metadata = await RecordingFileMetadata.load(for: url)
        }
    }

    private var savedDetail: String {
        var parts = [url.lastPathComponent]
        if metadata.thumbnail == nil, let durationLabel = metadata.durationLabel {
            parts.append(durationLabel)
        }
        if let sizeLabel = metadata.sizeLabel {
            parts.append(sizeLabel)
        }
        return parts.joined(separator: " · ")
    }
}

private struct SavedRecordingSummaryButton: View {
    let detail: String
    let path: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BlitzUI.mint.opacity(0.9))
                    Text("Recording saved")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize()
                }
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(hovering ? 0.78 : 0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 120, maxWidth: 180, alignment: .leading)
        .layoutPriority(-1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help("Show in Finder — \(path)")
    }
}

private struct SessionStatusText: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detail)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }
}

private struct ElapsedTimeText: View {
    let isPaused: Bool
    let elapsed: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPaused ? BlitzUI.warning : BlitzUI.recordRed)
                .frame(width: 7, height: 7)

            Text(elapsed)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isPaused ? 0.55 : 0.95))

            if isPaused {
                Text("Paused")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BlitzUI.warning)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 112, minHeight: 44, alignment: .leading)
    }
}

private struct FinishingProgressStatus: View {
    let title: String
    let detail: String?
    let progress: Double
    let percent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(percent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.85))
                .frame(width: 240)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .help(detail ?? title)
    }
}

private struct RecordingThumbnailButton: View {
    let image: NSImage?
    let durationLabel: String?
    var height: CGFloat = 68
    let help: String
    let action: () -> Void
    @State private var hovering = false

    private var width: CGFloat {
        guard let image, image.size.height > 0 else { return height * 16 / 9 }
        let ideal = height * image.size.width / image.size.height
        return min(max(ideal, height * 0.6), height * 1.9)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                    Image(systemName: "film")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Rectangle()
                    .fill(.black.opacity(hovering ? 0.35 : 0))
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                if let durationLabel {
                    Text(durationLabel)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(4)
                        .opacity(hovering ? 0 : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help(help)
    }
}

private struct DockDismissButton: View {
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.45))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help(help)
    }
}

private struct RecoveryAvailableView: View {
    @Bindable var vm: RecorderViewModel
    let recovery: RecordingRecoveryOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BlitzUI.warning)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording needs recovery")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BlitzUI.warning)
                    Text(recovery.reason)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recovery.takeDirectory.path)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(recovery.takeDirectory.path)
                }

                Spacer(minLength: 8)
            }

            Divider()
                .background(.white.opacity(0.07))

            ViewThatFits(in: .horizontal) {
                recoveryActionRow
                VStack(alignment: .leading, spacing: 8) {
                    recoveryPrimaryActionRow
                    recoverySecondaryActionRow
                }
            }
        }
        .frame(maxWidth: 560)
    }

    private var recoveryActionRow: some View {
        HStack(spacing: 8) {
            recoveryPrimaryActions
            recoverySecondaryActions
        }
    }

    private var recoveryPrimaryActionRow: some View {
        HStack(spacing: 8) {
            recoveryPrimaryActions
        }
    }

    private var recoverySecondaryActionRow: some View {
        HStack(spacing: 8) {
            recoverySecondaryActions
        }
    }

    @ViewBuilder
    private var recoveryPrimaryActions: some View {
        if recovery.canRetryExport {
            DockActionButton(title: "Retry Export", systemImage: "arrow.clockwise", help: "Try exporting the recovered source files again") {
                vm.retryRecoveredExport()
            }
        }

        DockActionButton(title: "Reveal Files", systemImage: "tray.full", help: recovery.takeDirectory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([recovery.takeDirectory])
        }
    }

    @ViewBuilder
    private var recoverySecondaryActions: some View {
        DockActionButton(title: "Export Settings", systemImage: "slider.horizontal.3") {
            vm.onPresentSettings?(.recording)
        }

        DockActionButton(title: "Dismiss", systemImage: "xmark") {
            vm.clearPostRecordingStatus()
        }
    }
}

private struct RecordingFileMetadata {
    let sizeLabel: String?
    let durationLabel: String?
    let thumbnail: NSImage?

    static let empty = RecordingFileMetadata(sizeLabel: nil, durationLabel: nil, thumbnail: nil)

    static func load(for url: URL) async -> RecordingFileMetadata {
        async let sizeLabel = fileSizeLabel(for: url)
        async let durationLabel = durationLabel(for: url)
        async let thumbnail = thumbnail(for: url)
        return await RecordingFileMetadata(sizeLabel: sizeLabel, durationLabel: durationLabel, thumbnail: thumbnail)
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let (cgImage, _) = try? await generator.image(at: .zero) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func fileSizeLabel(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let byteCount = attributes[.size] as? NSNumber else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: byteCount.int64Value, countStyle: .file)
    }

    private static func durationLabel(for url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.isValid,
              duration.seconds.isFinite,
              duration.seconds > 0 else {
            return nil
        }
        return formattedDuration(seconds: duration.seconds)
    }

    private static func formattedDuration(seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PauseButton: View {
    @Bindable var vm: RecorderViewModel
    @State private var hovering = false

    var body: some View {
        Button {
            vm.togglePause()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.14 : 0.08))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
        }
        .buttonStyle(RecordButtonPressStyle())
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .accessibilityLabel(helpText)
        .help(helpText)
    }

    private var symbol: String {
        vm.state == .paused ? "play.fill" : "pause.fill"
    }

    private var helpText: String {
        vm.state == .paused ? "Resume" : "Pause"
    }

    private var isEnabled: Bool {
        vm.state == .recording || vm.state == .paused
    }
}

private struct RecordButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RecordButton: View {
    @Bindable var vm: RecorderViewModel

    @State private var isHovering = false

    var body: some View {
        Button {
            vm.primaryAction()
        } label: {
            HStack(spacing: 9) {
                recordGlyph
                Text(actionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .padding(.horizontal, 16)
            .frame(minWidth: vm.state == .idle ? 112 : 94, minHeight: 44)
            .background(buttonFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                    .strokeBorder(BlitzUI.recordRed.opacity(isHovering ? 0.65 : 0.38), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
        }
        .buttonStyle(RecordButtonPressStyle())
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .help(vm.recordingBlockerDetail ?? helpText)
    }

    @ViewBuilder
    private var recordGlyph: some View {
        switch vm.state {
        case .idle:
            Circle()
                .fill(BlitzUI.recordRed)
                .frame(width: 12, height: 12)
        case .recording, .paused:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.96))
                .frame(width: 12, height: 12)
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .finishing:
            ProgressView()
                .controlSize(.small)
        }
    }

    private var buttonFill: Color {
        BlitzUI.recordRed.opacity(isHovering ? 0.32 : 0.22)
    }

    private var helpText: String {
        switch vm.state {
        case .idle: return "Start recording"
        case .recording, .paused: return "Stop recording"
        case .starting: return "Please wait"
        case .finishing: return "Saving…"
        }
    }

    private var actionTitle: String {
        switch vm.state {
        case .idle: return "Record"
        case .recording, .paused: return "Stop"
        case .starting: return "Starting"
        case .finishing: return "Saving"
        }
    }

    private var dimmed: Bool {
        switch vm.state {
        case .idle: return !vm.canStartRecording
        case .recording, .paused: return false
        case .starting, .finishing: return true
        }
    }

    private var enabled: Bool {
        switch vm.state {
        case .idle: return true
        case .recording, .paused: return true
        case .starting, .finishing: return false
        }
    }
}

#if DEBUG
@MainActor
private func bottomDockPreviewModel(warning: String? = nil) -> RecorderViewModel {
    let suiteName = "BlitzRecorder.BottomDockPreview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let coordinator = RecorderCoordinator(
        accessController: AccessController(defaults: defaults),
        defaults: defaults
    )
    let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
    vm.lastExportedURL = URL(fileURLWithPath: "/Volumes/harddrive/recordings/video-exa.mov")
    vm.lastExportedSourceTakeURL = URL(fileURLWithPath: "/Volumes/harddrive/recordings/sources/video-exa")
    vm.lastExportWarning = warning
    return vm
}

#Preview("Recording controls - compact") {
    let vm = bottomDockPreviewModel()
    vm.state = .recording
    return RecordingActionRow(vm: vm)
        .frame(width: 320)
        .padding(16)
        .background(BlitzUI.canvasBackground)
        .preferredColorScheme(.dark)
}

#Preview("Paused controls - compact") {
    let vm = bottomDockPreviewModel()
    vm.state = .paused
    return RecordingActionRow(vm: vm)
        .frame(width: 320)
        .padding(16)
        .background(BlitzUI.canvasBackground)
        .preferredColorScheme(.dark)
}

#Preview("Dock — recording saved") {
    RecordingActionRow(vm: bottomDockPreviewModel(), forcesSavedChip: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 1100)
        .background(.bar)
        .preferredColorScheme(.dark)
}

#Preview("Dock — saved with warning") {
    RecordingActionRow(
        vm: bottomDockPreviewModel(warning: "System audio was muted for part of this take."),
        forcesSavedChip: true
    )
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(width: 900)
    .background(.bar)
    .preferredColorScheme(.dark)
}
#endif
