import AppKit
import AVFoundation
import Foundation
import SwiftUI

struct BottomDock: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(spacing: 10) {
            if vm.state == .idle {
                if let recovery = vm.lastRecoveryOutput {
                    RecoveryAvailableView(vm: vm, recovery: recovery)
                } else if !vm.canStartRecording {
                    ReadinessIssueView(vm: vm)
                }
            }

            RecordingActionRow(vm: vm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct RecordingActionRow: View {
    @Bindable var vm: RecorderViewModel
    var forcesSavedChip = false

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 10) {
                switch vm.state {
                case .idle:
                    RecordingSettingsShortcut(vm: vm)
                case .recording, .paused:
                    PauseButton(vm: vm)
                case .starting, .finishing:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            RecordButton(vm: vm)

            HStack(spacing: 10) {
                switch vm.state {
                case .idle:
                    if let savedURL = savedExportURL {
                        SavedRecordingChip(
                            vm: vm,
                            url: savedURL,
                            sourceTakeURL: vm.lastExportedSourceTakeURL,
                            warning: vm.lastExportWarning
                        )
                    } else if vm.lastPostRecordingProjectOutput != nil {
                        ProjectReadyChip(vm: vm)
                    } else if let message = vm.idleStatusMessage {
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 320, alignment: .leading)
                            .help(message)
                    }
                case .starting:
                    SessionStatusText(title: vm.sessionProgressTitle, detail: vm.sessionProgressDetail)
                case .recording, .paused:
                    ElapsedTimeText(isPaused: vm.state == .paused, elapsed: vm.formattedElapsed)
                case .finishing:
                    FinishingProgressStatus(
                        title: vm.sessionProgressTitle,
                        detail: vm.sessionProgressDetail,
                        progress: vm.sessionProgressValue,
                        percent: vm.sessionProgressLabel
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct RecordingSettingsShortcut: View {
    @Bindable var vm: RecorderViewModel
    @State private var hovering = false

    var body: some View {
        Button {
            vm.onPresentSettings?(.recording)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(settingsSummary)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
            .foregroundStyle(.white.opacity(hovering ? 0.92 : 0.58))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help("Export settings")
    }

    private var settingsSummary: String {
        "\(vm.settings.outputResolution.displayName) · \(vm.settings.framesPerSecond) FPS"
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
                .font(.system(size: 10, weight: .bold))
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
        HStack(spacing: 10) {
            Button {
                vm.openEditor()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BlitzUI.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project ready")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.90))
                        Text(projectDetail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
            }
            .blitzGlassButton()
            .pointingHandCursor()
            .help("Open this take in Edit")

            ProjectActionsMenu(vm: vm)

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
            Button("Open in Edit") { vm.openEditor() }
            ProjectCorrectionMenuContent(vm: vm)
            Menu("Export As") {
                ForEach(OutputVideoFormat.allCases, id: \.self) { format in
                    Button(format.displayName) {
                        vm.exportLastProject(as: format)
                    }
                }
            }
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
                HStack(spacing: 6) {
                    DockActionButton(title: "Edit", systemImage: "rectangle.and.pencil.and.ellipsis", help: "Open this take in Edit") {
                        vm.openEditor()
                    }
                    ProjectActionsMenu(vm: vm)
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
                ProjectCorrectionMenuContent(vm: vm)
                Menu("Export As") {
                    ForEach(OutputVideoFormat.allCases, id: \.self) { format in
                        Button(format.displayName) {
                            vm.exportLastProject(as: format)
                        }
                    }
                }
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

private struct ProjectActionsMenu: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Menu {
            ProjectCorrectionMenuContent(vm: vm)
            Divider()
            Menu("Export As") {
                ForEach(OutputVideoFormat.allCases, id: \.self) { format in
                    Button(format.displayName) {
                        vm.exportLastProject(as: format)
                    }
                }
            }
            Button("Show Source Files") {
                vm.revealLastSourceTracks()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 26)
        }
        .menuStyle(.button)
        .controlSize(.small)
        .help("More take actions")
        .task(id: vm.lastExportedSourceTakeURL) {
            vm.refreshLastExportedProject()
        }
    }
}

private struct ProjectCorrectionMenuContent: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        if let project = vm.lastExportedProject, !project.sceneEvents.isEmpty {
            if project.sceneEvents.count == 1 {
                Menu("Video Mix") {
                    correctionButtons(eventIndex: 0, event: project.sceneEvents[0])
                }
            } else {
                Menu("Mix Changes") {
                    ForEach(Array(project.sceneEvents.enumerated()), id: \.offset) { index, event in
                        Menu(segmentTitle(for: event, index: index)) {
                            correctionButtons(eventIndex: index, event: event)
                        }
                    }
                }
            }
        } else {
            Button("No editable video mix") {}
                .disabled(true)
        }
    }

    @ViewBuilder
    private func correctionButtons(
        eventIndex: Int,
        event: RecordingProject.SceneEventSnapshot
    ) -> some View {
        let selected = selectedCorrection(for: event)
        ForEach(RecordingProjectSceneCorrection.allCases, id: \.self) { correction in
            Button {
                vm.applyProjectSceneCorrection(eventIndex: eventIndex, correction: correction)
            } label: {
                Label(
                    correction.displayName,
                    systemImage: correction == selected ? "checkmark" : correction.symbolName
                )
            }
        }
    }

    private func selectedCorrection(for event: RecordingProject.SceneEventSnapshot) -> RecordingProjectSceneCorrection {
        let sources = Set(event.scene.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        let hasScreen = sources.contains(.screen)
        let hasCamera = sources.contains(.camera)
        switch (hasScreen, hasCamera) {
        case (true, true):
            return .screenAndCamera
        case (true, false):
            return .screenOnly
        case (false, true):
            return .cameraOnly
        default:
            return .screenAndCamera
        }
    }

    private func segmentTitle(for event: RecordingProject.SceneEventSnapshot, index: Int) -> String {
        if index == 0 && event.time == 0 {
            return "From 00:00"
        }
        return "From \(formatTime(event.time))"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
        VStack(alignment: .leading, spacing: 1) {
            Text(elapsed)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isPaused ? 0.55 : 0.95))
            if isPaused {
                Text("Paused")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BlitzUI.warning)
            }
        }
    }
}

private struct FinishingProgressStatus: View {
    let title: String
    let detail: String?
    let progress: Double
    let percent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Text(percent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.85))
                .frame(width: 200)
        }
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

private struct ReadinessIssueView: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BlitzUI.warning)

            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(fullExplanation)

            Spacer(minLength: 12)

            DetailsLink { vm.openReadinessDetails() }
        }
        .frame(maxWidth: .infinity)
    }

    private var message: String {
        if !vm.accessController.canRenderExport {
            return "Recording unavailable"
        }
        let blockers = vm.recordingReadiness.blockers
        return blockers.isEmpty ? vm.recordingReadiness.detail : blockers.shortSummary
    }

    private var fullExplanation: String {
        let sentences = vm.recordingReadiness.blockers.map(\.sentence)
        return sentences.isEmpty ? message : sentences.joined(separator: "\n")
    }
}

private struct DetailsLink: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("Details")
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(hovering ? 1 : 0.78))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }
}

private struct PauseButton: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.togglePause()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 40, height: 40)
        }
        .blitzGlassButton()
        .disabled(!isEnabled)
        .pointingHandCursor()
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
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RecordButton: View {
    @Bindable var vm: RecorderViewModel

    private let diameter: CGFloat = 56
    @State private var isHovering = false

    private var lifted: Bool { isHovering && enabled && !dimmed }

    var body: some View {
        Button {
            vm.primaryAction()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.14), lineWidth: 2)
                    .frame(width: diameter, height: diameter)

                recordGlyph
            }
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .scaleEffect(lifted ? 1.03 : 1)
            .animation(.easeOut(duration: 0.16), value: lifted)
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
                .frame(width: diameter - 8, height: diameter - 8)
        case .recording, .paused:
            ZStack {
                Circle()
                    .strokeBorder(BlitzUI.recordRed, lineWidth: 4)
                    .frame(width: diameter - 6, height: diameter - 6)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.95))
                    .frame(width: 18, height: 18)
            }
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .finishing:
            Circle()
                .fill(BlitzUI.recordRed)
                .frame(width: diameter - 8, height: diameter - 8)
        }
    }

    private var helpText: String {
        switch vm.state {
        case .idle: return "Start recording"
        case .recording, .paused: return "Stop recording"
        case .starting: return "Please wait"
        case .finishing: return "Saving…"
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
