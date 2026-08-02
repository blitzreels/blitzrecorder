import AppKit
import AVFoundation
import CoreImage
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

private struct EditorToolbarPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EditorExportOptionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? BlitzUI.mint : Color.white.opacity(0.68))
            .background(
                isSelected ? BlitzUI.mint.opacity(0.13) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.045),
                in: .rect(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? BlitzUI.mint.opacity(0.42) : Color.white.opacity(0.055),
                        lineWidth: 1
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum EditorInspectorTab: String, CaseIterable {
    case layout = "Layout"
    case canvas = "Canvas"
    case audio = "Audio"

    var systemImage: String {
        switch self {
        case .layout: return "rectangle.3.group"
        case .canvas: return "paintpalette"
        case .audio: return "waveform"
        }
    }
}

private struct EditorExportPresetRequest {
    let preset: ExportPerformancePreset
    let project: RecordingProject
}

enum EditorScenePresetSourceCorrection {
    static func correction(for preset: ScenePreset) -> RecordingProjectSceneCorrection? {
        switch preset {
        case .screenFullscreen:
            return .screenOnly
        case .webcamFullscreen:
            return .cameraOnly
        default:
            return nil
        }
    }
}

struct EditorView: View {
    @Bindable var vm: RecorderViewModel
    @State private var library = EditorMediaLibrary()
    @State private var playback = EditorPlaybackController()
    @State private var assets: [EditorAsset] = []
    @State private var selection: EditorSelection?
    @State private var selectedFormat: OutputVideoFormat = .mov
    @State private var selectedResolution: OutputResolution = .p1080
    @State private var selectedExportFramesPerSecond = 60
    @State private var selectedExportQuality: ExportVideoQuality = .high
    @State private var selectedExportPreset: ExportPerformancePreset = .balanced
    @State private var backgroundMusic: ExportBackgroundMusic?
    @State private var backgroundMusicBookmarkData: Data?
    @State private var isExportPopoverPresented = false
    @State private var reloadTask: Task<Void, Never>?
    @State private var sceneEvents: [RecordingSceneEvent] = []
    @State private var layoutDraft: EditorLayoutDraft?
    @State private var screenZoomDraft: Double?
    @State private var cameraZoomDraft: Double?
    @State private var canvasSceneDraft: RecordingScene?
    @State private var canvasCommitTask: Task<Void, Never>?
    @State private var preservesCanvasPreviewOnNextProjectRefresh = false
    @State private var editErrorMessage: String?
    @State private var inspectorTab: EditorInspectorTab = .layout
    @State private var aspectRatioLockedKinds: Set<SceneLayerKind> = [.screen, .camera]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

            if vm.state == .finishing {
                editorExportProgressBar
            } else if let error = vm.lastExportError {
                editorExportErrorBar(error)
            } else if let exported = vm.lastExportSucceededURL {
                editorExportSuccessBar(exported)
            }

            divider

            HStack(spacing: 0) {
                playerColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BlitzUI.canvasBackground)

                verticalDivider

                inspector
                    .frame(width: 312)
                    .background(.regularMaterial)
            }
            .frame(maxHeight: .infinity)

            divider

            EditorTimelineView(
                project: vm.lastExportedProject,
                assets: assets,
                library: library,
                draftScene: layoutDraft?.scene ?? canvasSceneDraft,
                draftSceneEventIndex: layoutDraft?.eventIndex ?? (canvasSceneDraft == nil ? nil : currentEventIndex),
                duration: timelineDuration,
                playbackTime: playback.currentTime,
                liveTime: { playback.displayTime() },
                isPlaying: playback.isPlaying,
                playbackRate: playback.playbackRate,
                selection: $selection,
                onSeek: { playback.scrub(to: $0) },
                onSeekEnded: { playback.endScrub() },
                onPrevious: { playback.seek(to: previousBoundary()) },
                onTogglePlayback: { playback.togglePlayback() },
                onNext: { playback.seek(to: nextBoundary()) },
                onPlaybackRateChange: { playback.setPlaybackRate($0) },
                isInteractive: playback.isReady,
                hiddenAssetIDs: hiddenAssetIDs,
                mutedAssetIDs: mutedAssetIDs,
                toggleableAssetIDs: toggleableAssetIDs,
                onToggleTrack: { toggleTrack($0) },
                onSplit: splitAtPlayhead,
                onDeleteCut: deleteSelectedCut,
                canDeleteCut: canDeleteSelectedCut
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .background(Color.white.opacity(0.018))
        }
        .task(id: vm.lastExportedSourceTakeURL) {
            vm.refreshLastExportedProject()
            reloadTask?.cancel()
            let task = Task { await reloadProject() }
            reloadTask = task
            await task.value
        }
        .onChange(of: vm.lastExportedProject) {
            reloadTask?.cancel()
            let preservesPreviewSceneOverride = preservesCanvasPreviewOnNextProjectRefresh
            preservesCanvasPreviewOnNextProjectRefresh = false
            let task = Task {
                await refreshProject(preservesPreviewSceneOverride: preservesPreviewSceneOverride)
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                layoutDraft = nil
                screenZoomDraft = nil
                cameraZoomDraft = nil
                canvasSceneDraft = nil
            }
            reloadTask = task
        }
        .onDisappear {
            reloadTask?.cancel()
            reloadTask = nil
            canvasCommitTask?.cancel()
            canvasCommitTask = nil
            playback.teardown()
        }
        .onChange(of: selection) { _, selection in
            switch selection {
            case .segment:
                inspectorTab = .layout
            case .asset(let id):
                let kind = assets.first(where: { $0.id == id })?.kind
                inspectorTab = kind == .microphone || kind == .systemAudio
                    ? .audio
                    : .layout
            case nil:
                inspectorTab = .layout
            }
        }
        .overlay {
            EditorKeyboardShortcutView { event in
                handleKeyboardShortcut(event)
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
    }

    private func reloadProject() async {
        guard !Task.isCancelled else { return }
        guard let project = vm.lastExportedProject else {
            assets = []
            sceneEvents = []
            return
        }
        sceneEvents = TakeFileStore().sceneEvents(from: project)
        applyEditorState(project)
        assets = EditorAsset.assets(project: project, finalVideoURL: vm.lastExportedURL)
        async let media: Void = library.loadAssets(assets)
        await playback.load(project: project, baseSettings: vm.settings)
        await media
    }

    private func refreshProject(preservesPreviewSceneOverride: Bool) async {
        guard !Task.isCancelled else { return }
        guard let project = vm.lastExportedProject else {
            await reloadProject()
            return
        }
        sceneEvents = TakeFileStore().sceneEvents(from: project)
        applyEditorState(project)
        assets = EditorAsset.assets(project: project, finalVideoURL: vm.lastExportedURL)

        let refreshed = playback.refreshSceneTimeline(EditorPlaybackSceneTimelineUpdate(
            project: project,
            baseSettings: vm.settings,
            preservesPreviewSceneOverride: preservesPreviewSceneOverride
        ))
        if !refreshed {
            await reloadProject()
        } else {
            playback.applyEditorState(project.editorState)
        }
    }

    private func fillWindow() {
        vm.onFillEditorWindow?()
    }

    private var project: RecordingProject? {
        vm.lastExportedProject
    }

    private var timelineDuration: Double {
        if playback.duration > 0 {
            return playback.duration
        }
        let lastEvent = project?.sceneEvents.last?.time ?? 0
        return lastEvent > 0 ? lastEvent + 1 : 0
    }

    private var captureLayout: CaptureLayout? {
        project.flatMap { CaptureLayout(rawValue: $0.settings.layout) }
    }

    private var canvasAspectRatio: CGFloat {
        if playback.renderSize.width > 0, playback.renderSize.height > 0 {
            return playback.renderSize.width / playback.renderSize.height
        }
        return captureLayout?.aspectRatio ?? 16.0 / 9.0
    }

    private var ratioLabel: String {
        switch captureLayout {
        case .vertical: return "9:16"
        case .horizontal: return "16:9"
        case nil: return "—"
        }
    }

    private var resolutionLabel: String {
        guard let project,
              let resolution = OutputResolution(rawValue: project.settings.outputResolution) else {
            return "—"
        }
        if let captureLayout {
            let size = resolution.dimensions(for: captureLayout)
            return "\(size.width) × \(size.height)"
        }
        return resolution.displayName
    }

    private var segmentBoundaries: [Double] {
        (project?.sceneEvents.map(\.time) ?? []).sorted()
    }

    private var hiddenAssetIDs: Set<String> {
        Set(assets.filter { asset in
            layerKind(for: asset).map(playback.hiddenKinds.contains) ?? false
        }.map(\.id))
    }

    private var mutedAssetIDs: Set<String> {
        Set(assets.filter { asset in
            audioSource(for: asset).map(playback.mutedSources.contains) ?? false
        }.map(\.id))
    }

    private var toggleableAssetIDs: Set<String> {
        Set(assets.filter { asset in
            if let kind = layerKind(for: asset) {
                guard playback.hideableKinds.contains(kind) else { return false }
                let visibleVideoCount = playback.hideableKinds.subtracting(playback.hiddenKinds).count
                return playback.hiddenKinds.contains(kind) || visibleVideoCount > 1
            }
            if let source = audioSource(for: asset) {
                return playback.muteableSources.contains(source)
            }
            return false
        }.map(\.id))
    }

    private func layerKind(for asset: EditorAsset) -> SceneLayerKind? {
        switch asset.kind {
        case .screen: return .screen
        case .camera: return .camera
        default: return nil
        }
    }

    private func audioSource(for asset: EditorAsset) -> CaptureSource? {
        switch asset.kind {
        case .microphone: return .microphone
        case .systemAudio: return .systemAudio
        default: return nil
        }
    }

    private func toggleTrack(_ asset: EditorAsset) {
        if let kind = layerKind(for: asset) {
            playback.setHidden(!playback.hiddenKinds.contains(kind), kind: kind)
            persistEditorState("Change Export Track")
        } else if let source = audioSource(for: asset) {
            playback.setMuted(!playback.mutedSources.contains(source), source: source)
            persistEditorState("Change Export Track")
        }
    }

    private func asset(for kind: SceneLayerKind) -> EditorAsset? {
        switch kind {
        case .screen: return assets.first { $0.kind == .screen }
        case .camera: return assets.first { $0.kind == .camera }
        }
    }

    private var selectedVideoLayerKind: SceneLayerKind? {
        guard case .asset(let id) = selection,
              let asset = assets.first(where: { $0.id == id }) else {
            return nil
        }
        return layerKind(for: asset)
    }


    private var toolbar: some View {
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
            .buttonStyle(EditorToolbarPressButtonStyle())
            .pointingHandCursor()
            .help("Return to projects")

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: 18)
                .padding(.leading, 4)
                .padding(.trailing, 16)

            Text(project?.displayTitle ?? "Last recording")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .allowsWindowActivationEvents(true)
                .onTapGesture(count: 2, perform: fillWindow)

            Spacer(minLength: 24)
                .contentShape(.rect)
                .allowsWindowActivationEvents(true)
                .onTapGesture(count: 2, perform: fillWindow)

            exportButton
        }
        .frame(height: 44)
    }

    private func sourceResolution(for project: RecordingProject) -> OutputResolution {
        OutputResolution(rawValue: project.settings.outputResolution) ?? .p1080
    }

    private func applyEditorState(_ project: RecordingProject) {
        if let recipe = project.editorState.exportRecipe,
           let preset = ExportPerformancePreset(rawValue: recipe.preset),
           let format = OutputVideoFormat(rawValue: recipe.format),
           let resolution = OutputResolution(rawValue: recipe.resolution),
           let quality = ExportVideoQuality(rawValue: recipe.quality) {
            selectedExportPreset = preset
            selectedFormat = format
            selectedResolution = resolution
            selectedExportFramesPerSecond = recipe.framesPerSecond
            selectedExportQuality = quality
        } else {
            selectedFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat)
                ?? vm.settings.outputVideoFormat
            applyExportPreset(EditorExportPresetRequest(preset: .balanced, project: project))
        }
        backgroundMusicBookmarkData = project.editorState.backgroundMusicBookmarkData
        backgroundMusic = resolvedBackgroundMusic(project.editorState)
    }

    private func resolvedBackgroundMusic(
        _ state: RecordingProject.EditorStateSnapshot
    ) -> ExportBackgroundMusic? {
        guard let path = state.backgroundMusicPath else { return nil }
        var url = URL(fileURLWithPath: path)
        if let bookmarkData = state.backgroundMusicBookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                url = resolvedURL
                if isStale {
                    backgroundMusicBookmarkData = RecordingSettingsStore.bookmarkData(for: resolvedURL)
                }
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return ExportBackgroundMusic(url: url, volume: state.backgroundMusicVolume ?? 0.18)
    }

    private var editorStateSnapshot: RecordingProject.EditorStateSnapshot {
        RecordingProject.EditorStateSnapshot(
            hiddenVideoSources: playback.hiddenKinds.map(\.rawValue).sorted(),
            mutedAudioSources: playback.mutedSources.map(\.rawValue).sorted(),
            backgroundMusicPath: backgroundMusic?.url.path,
            backgroundMusicBookmarkData: backgroundMusicBookmarkData,
            backgroundMusicVolume: backgroundMusic?.volume,
            exportRecipe: RecordingProject.ExportRecipeSnapshot(
                preset: selectedExportPreset.rawValue,
                format: selectedFormat.rawValue,
                resolution: selectedResolution.rawValue,
                framesPerSecond: selectedExportFramesPerSecond,
                quality: selectedExportQuality.rawValue
            )
        )
    }

    private func persistEditorState(_ actionName: String) {
        guard vm.applyProjectEditorState(.init(
            editorState: editorStateSnapshot,
            actionName: actionName
        )) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private var exportButton: some View {
        Button {
            isExportPopoverPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: vm.state == .finishing ? "hourglass" : "square.and.arrow.up")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(vm.state == .finishing ? "Exporting" : "Export")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.black.opacity(0.82))
            .padding(.leading, 15)
            .padding(.trailing, 17)
            .frame(height: 40)
            .background(BlitzUI.mint, in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .buttonStyle(EditorToolbarPressButtonStyle())
        .pointingHandCursor()
        .disabled(project == nil || vm.state != .idle)
        .opacity(project == nil ? 0.45 : 1)
        .help("Choose export settings")
        .popover(isPresented: $isExportPopoverPresented, arrowEdge: .top) {
            exportPopover
        }
    }

    private var exportPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BlitzUI.mint)
                    .frame(width: 32, height: 32)
                    .background(BlitzUI.mint.opacity(0.11), in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export video")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text("Compress the final composed video. Recorded sources stay unchanged.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        exportRowLabel("Export preset")
                        HStack(spacing: 6) {
                            ForEach(ExportPerformancePreset.allCases, id: \.rawValue) { preset in
                                exportPerformancePresetButton(preset)
                            }
                        }
                    }

                    Text(selectedExportPreset.plainDescription)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.leading, 102)
                }
                .padding(12)

                exportSettingsDivider

                HStack(spacing: 10) {
                    exportRowLabel("Export format")
                    HStack(spacing: 6) {
                        ForEach(OutputVideoFormat.allCases, id: \.rawValue) { format in
                            exportFormatButton(format)
                        }
                    }
                }
                .padding(12)

                exportSettingsDivider

                HStack(spacing: 10) {
                    exportRowLabel("Export resolution")
                    HStack(spacing: 6) {
                        ForEach(OutputResolution.allCases, id: \.rawValue) { resolution in
                            exportResolutionButton(resolution)
                        }
                    }
                }
                .padding(12)

                exportSettingsDivider

                HStack(spacing: 10) {
                    exportRowLabel("Export FPS")
                    HStack(spacing: 6) {
                        ForEach(RecordingSettings.supportedFrameRates, id: \.self) { framesPerSecond in
                            exportFrameRateButton(framesPerSecond)
                        }
                    }
                }
                .padding(12)

                exportSettingsDivider

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        exportRowLabel("Export quality")
                        HStack(spacing: 6) {
                            ForEach(ExportVideoQuality.allCases, id: \.rawValue) { quality in
                                exportQualityButton(quality)
                            }
                        }
                    }

                    Text("\(selectedExportQuality.plainDescription) · Final video only")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.leading, 102)
                }
                .padding(12)
            }
            .background(Color.black.opacity(0.16), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.075), lineWidth: 1)
            }

            if let backgroundMusic {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundStyle(BlitzUI.mint.opacity(0.82))
                    Text("\(backgroundMusic.url.lastPathComponent) · \(musicVolumeLabel)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(Color.white.opacity(0.045), in: .rect(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("READY TO EXPORT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.36))
                Text(exportSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)

            Button {
                exportVideo()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text("Export video")
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.black.opacity(0.84))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(BlitzUI.mint, in: .rect(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Save to \(vm.settings.outputDirectory.path)")
        }
        .padding(16)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private func exportRowLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.52))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(width: 92, alignment: .leading)
    }

    private var exportSettingsDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.065))
            .frame(height: 1)
            .padding(.leading, 114)
    }

    private func exportFormatButton(_ format: OutputVideoFormat) -> some View {
        let selected = format == selectedFormat
        return Button {
            selectedFormat = format
            persistEditorState("Change Export Format")
        } label: {
            Text(format.displayName)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(EditorExportOptionButtonStyle(isSelected: selected))
        .pointingHandCursor()
    }

    private func exportPerformancePresetButton(_ preset: ExportPerformancePreset) -> some View {
        let selected = preset == selectedExportPreset
        return Button {
            guard let project else { return }
            if preset == .maximum,
               sourceResolution(for: project) == .p2160,
               !vm.accessController.canUse4KExport {
                _ = vm.accessController.requirePaidFeature("4K export")
                return
            }
            applyExportPreset(EditorExportPresetRequest(preset: preset, project: project))
            persistEditorState("Change Export Preset")
        } label: {
            Text(preset.displayName)
                .font(.system(size: 10.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(EditorExportOptionButtonStyle(isSelected: selected))
        .pointingHandCursor()
    }

    private func exportResolutionButton(_ resolution: OutputResolution) -> some View {
        let selected = resolution == selectedResolution
        let locked = resolution == .p2160 && !vm.accessController.canUse4KExport
        return Button {
            guard !locked else {
                _ = vm.accessController.requirePaidFeature("4K export")
                return
            }
            selectedResolution = resolution
            selectedExportPreset = .custom
            persistEditorState("Change Export Resolution")
        } label: {
            HStack(spacing: 4) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(resolution.displayName)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(EditorExportOptionButtonStyle(isSelected: selected))
        .pointingHandCursor()
    }

    private func exportFrameRateButton(_ framesPerSecond: Int) -> some View {
        let selected = framesPerSecond == selectedExportFramesPerSecond
        return Button {
            selectedExportFramesPerSecond = framesPerSecond
            selectedExportPreset = .custom
            persistEditorState("Change Export Frame Rate")
        } label: {
            Text("\(framesPerSecond) fps")
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(EditorExportOptionButtonStyle(isSelected: selected))
        .pointingHandCursor()
    }

    private func exportQualityButton(_ quality: ExportVideoQuality) -> some View {
        let selected = quality == selectedExportQuality
        return Button {
            selectedExportQuality = quality
            selectedExportPreset = .custom
            persistEditorState("Change Export Quality")
        } label: {
            Text(quality.displayName)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(EditorExportOptionButtonStyle(isSelected: selected))
        .pointingHandCursor()
    }

    private var exportFrameRate: Int {
        selectedExportFramesPerSecond
    }

    private var exportPerformanceProfile: ExportPerformanceProfile {
        ExportPerformanceProfile.resolved(
            preset: selectedExportPreset,
            sourceResolution: project.map { sourceResolution(for: $0) } ?? vm.settings.outputResolution,
            sourceFramesPerSecond: project?.settings.framesPerSecond ?? vm.settings.framesPerSecond,
            customResolution: selectedResolution,
            customFramesPerSecond: selectedExportFramesPerSecond,
            customVideoQuality: selectedExportQuality
        )
    }

    private var exportBitrate: Int {
        selectedExportQuality.videoBitrate(
            baseBitrate: SocialVideoEncoding.videoBitrate(
                resolution: selectedResolution,
                fps: exportFrameRate
            )
        )
    }

    private var exportSummary: String {
        let layout = captureLayout ?? vm.settings.layout
        let dimensions = selectedResolution.dimensions(for: layout)
        let bitrate = Double(exportBitrate) / 1_000_000
        let estimatedBytes = Int64(max(0, timelineDuration) * Double(exportBitrate + 192_000) / 8)
        let estimatedSize = ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
        let bitrateLabel = String(format: "%.1f", bitrate)
        return "\(dimensions.width) × \(dimensions.height) · Export FPS \(exportFrameRate) · "
            + "HEVC · \(bitrateLabel) Mbps · ~\(estimatedSize)"
    }

    private func exportVideo() {
        let profile = exportPerformanceProfile
        if profile.resolution == .p2160, !vm.accessController.canUse4KExport {
            _ = vm.accessController.requirePaidFeature("4K export")
            return
        }
        isExportPopoverPresented = false
        vm.exportLastProject(EditorExportRequest(
            outputFormat: selectedFormat,
            performanceProfile: profile,
            hiddenVideoSources: playback.hiddenKinds,
            mutedAudioSources: playback.mutedSources,
            backgroundMusic: backgroundMusic
        ))
    }

    private func applyExportPreset(_ request: EditorExportPresetRequest) {
        let sourceResolution = sourceResolution(for: request.project)
        let profile = ExportPerformanceProfile.resolved(
            preset: request.preset,
            sourceResolution: sourceResolution,
            sourceFramesPerSecond: request.project.settings.framesPerSecond,
            customResolution: selectedResolution,
            customFramesPerSecond: selectedExportFramesPerSecond,
            customVideoQuality: selectedExportQuality
        )
        selectedExportPreset = request.preset
        selectedResolution = profile.resolution
        selectedExportFramesPerSecond = profile.framesPerSecond
        selectedExportQuality = profile.videoQuality
    }

    private var editorExportProgressBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.doc.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BlitzUI.mint)
                .frame(width: 22, height: 22)
                .background(BlitzUI.mint.opacity(0.14), in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(vm.sessionProgressTitle.isEmpty ? "Exporting" : vm.sessionProgressTitle)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.86))
                    Text(vm.sessionProgressLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.68))
                    if let detail = vm.sessionProgressDetail {
                        Text(detail)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                ProgressView(value: vm.sessionProgressValue)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.mint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.22))
    }

    private func editorExportSuccessBar(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BlitzUI.mint)
                .frame(width: 22, height: 22)
                .background(BlitzUI.mint.opacity(0.14), in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text("Exported")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(url.path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Reveal in Finder") { vm.revealLastExportOrSource() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(BlitzUI.mint)
            Button {
                vm.lastExportSucceededURL = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(BlitzUI.mint.opacity(0.08))
    }

    private func editorExportErrorBar(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BlitzUI.warning)
                .frame(width: 22, height: 22)
                .background(BlitzUI.warning.opacity(0.14), in: .rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text("Export failed")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try again") { exportVideo() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(BlitzUI.mint)
            Button {
                vm.lastExportError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(BlitzUI.warning.opacity(0.1))
    }


    private var playerColumn: some View {
        canvasStage
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }

    private var canvasStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)

            if playback.isReady {
                EditorCompositedPlayer(
                    controller: playback,
                    renderSize: playback.renderSize,
                    previewSceneRevision: playback.previewSceneRevision
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 12))
                    .allowsHitTesting(false)
            }

            if playback.isReady {
                EditorCanvasLayerOverlay(
                    layers: displayedCanvasLayers,
                    onSelect: { layer in
                        if let id = layer.assetID {
                            selection = .asset(id)
                        }
                    },
                    onMove: { kind, translation, ended in
                        handleLayerMove(kind: kind, translation: translation, ended: ended)
                    },
                    onResize: { kind, anchor, translation, ended in
                        handleLayerResize(kind: kind, anchor: anchor, translation: translation, ended: ended)
                    }
                )
            } else if layoutDraft == nil, let error = playback.loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BlitzUI.warning)
                    Text("The preview could not be built.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else if layoutDraft == nil {
                Color.clear
            }
        }
        .aspectRatio(canvasAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
        }
        .overlay(alignment: .top) {
            Text(ratioLabel)
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Color.black.opacity(0.55), in: .capsule)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let editErrorMessage {
                Label(editErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BlitzUI.warning)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65), in: .capsule)
                    .padding(.bottom, 10)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        self.editErrorMessage = nil
                    }
            }
        }
    }

    private var currentEventIndex: Int {
        let time = playback.currentTime
        var index = 0
        for (i, event) in sceneEvents.enumerated() where event.time <= time + 0.0001 {
            index = i
        }
        return index
    }

    private var currentEventScene: RecordingScene? {
        sceneEvents.indices.contains(currentEventIndex) ? sceneEvents[currentEventIndex].scene : nil
    }

    private func canEditLayout(of scene: RecordingScene) -> Bool {
        playback.isReady
            && !scene.enabledSources.intersection([.screen, .camera]).isEmpty
    }

    private var displayedCanvasLayers: [EditorCanvasLayer] {
        let frames: [(kind: SceneLayerKind, frame: CGRect)]
        let editable: Bool
        let draftScene = EditorCanvasOverlaySceneResolver.scene(request: .init(
            layoutDraftScene: layoutDraft?.scene,
            canvasDraftScene: canvasSceneDraft
        ))
        if let draftScene {
            frames = playback.layerFrames(for: draftScene)
            editable = true
        } else {
            frames = playback.layerFrames(at: playback.currentTime)
            editable = currentEventScene.map(canEditLayout(of:)) ?? false
        }
        return frames.map { kind, frame in
            let asset = asset(for: kind)
            return EditorCanvasLayer(
                kind: kind,
                assetID: asset?.id,
                frame: frame,
                displayAspectRatio: frame.height > 0 ? frame.width / frame.height * canvasAspectRatio : 1,
                isAspectRatioLocked: aspectRatioLockedKinds.contains(kind),
                isSelected: asset.map { selection == .asset($0.id) } ?? false,
                isEditable: editable
            )
        }
    }

    private func ensureLayoutDraft() -> EditorLayoutDraft? {
        if let layoutDraft { return layoutDraft }
        playback.pauseForEditing()
        let index = currentEventIndex
        guard sceneEvents.indices.contains(index) else { return nil }
        let event = sceneEvents[index]
        guard canEditLayout(of: event.scene) else { return nil }
        let transitionEnd = event.time + event.transition.duration
        if playback.currentTime < transitionEnd {
            playback.seek(to: min(transitionEnd, timelineDuration))
        }
        let draft = EditorLayoutDraft(
            eventIndex: index,
            startLayout: event.scene.sceneLayout,
            startCameraContentMode: event.scene.cameraContentMode,
            scene: event.scene
        )
        layoutDraft = draft
        return draft
    }

    private func handleLayerMove(kind: SceneLayerKind, translation: CGSize, ended: Bool) {
        guard var draft = ensureLayoutDraft() else { return }
        if let asset = asset(for: kind) {
            selection = .asset(asset.id)
        }
        var frame = layoutFrame(kind, in: draft.startLayout)
        frame.origin.x += translation.width
        frame.origin.y -= translation.height
        setLayoutFrame(SceneLayerResizing.clamped(frame), kind: kind, in: &draft.scene.sceneLayout)
        layoutDraft = draft
        playback.setPreviewSceneOverride(draft.scene, at: playback.currentTime)
        if ended {
            commitLayoutDraft(draft)
        }
    }

    private func handleLayerResize(kind: SceneLayerKind, anchor: ResizeAnchor, translation: CGSize, ended: Bool) {
        guard var draft = ensureLayoutDraft() else { return }
        let start = resizeStartFrame(kind: kind, draft: draft)
        let resized = SceneLayerResizing.resized(
            start,
            delta: CGPoint(x: translation.width, y: -translation.height),
            anchor: anchor,
            aspectRatio: aspectRatioLockedKinds.contains(kind) && start.height > 0
                ? start.width / start.height
                : nil
        )
        if kind == .camera, !aspectRatioLockedKinds.contains(kind) || !anchor.keepsAspectRatio {
            draft.scene.cameraContentMode = .fill
        }
        setLayoutFrame(resized, kind: kind, in: &draft.scene.sceneLayout)
        layoutDraft = draft
        playback.setPreviewSceneOverride(draft.scene, at: playback.currentTime)
        if ended {
            commitLayoutDraft(draft)
        }
    }

    private func resizeStartFrame(kind: SceneLayerKind, draft: EditorLayoutDraft) -> CGRect {
        guard kind == .camera, draft.scene.cameraContentMode == .fit else {
            return layoutFrame(kind, in: draft.startLayout)
        }
        var startScene = draft.scene
        startScene.sceneLayout = draft.startLayout
        guard let visibleFrame = playback.layerFrames(for: startScene).first(where: { $0.kind == kind })?.frame else {
            return layoutFrame(kind, in: draft.startLayout)
        }
        return layoutFrame(fromUpperLeftNormalizedFrame: visibleFrame)
    }

    private func layoutFrame(fromUpperLeftNormalizedFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: 1 - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func commitLayoutDraft(_ draft: EditorLayoutDraft) {
        guard draft.scene.sceneLayout != draft.startLayout
                || draft.scene.cameraContentMode != draft.startCameraContentMode else {
            layoutDraft = nil
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            return
        }
        let before = vm.lastExportedProject
        let succeeded = vm.applyProjectSceneEdit(eventIndex: draft.eventIndex) {
            $0.sceneLayout = draft.scene.sceneLayout
            $0.cameraContentMode = draft.scene.cameraContentMode
        }
        if !succeeded {
            layoutDraft = nil
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = "The layout change could not be saved."
        } else if vm.lastExportedProject == before {
            layoutDraft = nil
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
        }
    }

    private func layoutFrame(_ kind: SceneLayerKind, in layout: SceneLayout) -> CGRect {
        kind == .screen ? layout.screenFrame : layout.cameraFrame
    }

    private func setLayoutFrame(_ frame: CGRect, kind: SceneLayerKind, in layout: inout SceneLayout) {
        if kind == .screen {
            layout.screenFrame = frame
        } else {
            layout.cameraFrame = frame
        }
    }

    private func previousBoundary() -> Double {
        let boundaries = segmentBoundaries.filter { $0 < playback.currentTime - 0.25 }
        return boundaries.last ?? 0
    }

    private func nextBoundary() -> Double {
        let boundaries = segmentBoundaries.filter { $0 > playback.currentTime + 0.25 }
        return boundaries.first ?? timelineDuration
    }

    @discardableResult
    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)
        let hasControl = flags.contains(.control)
        let hasShift = flags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if hasCommand {
            guard !hasOption, !hasControl, key == "b" else { return false }
            splitAtPlayhead()
            return true
        }
        guard !hasOption, !hasControl else { return false }

        switch event.keyCode {
        case 49:
            playback.togglePlayback()
            return true
        case 123:
            hasShift ? playback.seek(by: -1) : playback.step(byFrames: -1)
            return true
        case 124:
            hasShift ? playback.seek(by: 1) : playback.step(byFrames: 1)
            return true
        case 125:
            playback.seek(to: nextBoundary())
            return true
        case 126:
            playback.seek(to: previousBoundary())
            return true
        case 51, 117:
            deleteSelectedCut()
            return true
        default:
            break
        }

        switch key {
        case "b", "s":
            splitAtPlayhead()
            return true
        case "h", "m":
            return toggleSelectedAsset()
        case "l":
            playback.playForwardOrIncreaseRate()
            return true
        default:
            return false
        }
    }

    private func splitAtPlayhead() {
        guard playback.isReady else { return }
        layoutDraft = nil
        playback.setPreviewSceneOverride(nil, at: playback.currentTime)
        let insertIndex = sceneEvents.filter { $0.time < playback.currentTime }.count
        if vm.splitProjectScene(at: playback.currentTime, duration: timelineDuration) {
            selection = .segment(max(0, insertIndex))
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    private func deleteSelectedCut() {
        guard case .segment(let index) = selection else {
            editErrorMessage = "Select a segment cut to remove."
            return
        }
        if vm.removeProjectSceneEvent(eventIndex: index) {
            selection = .segment(max(0, index - 1))
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    @discardableResult
    private func toggleSelectedAsset() -> Bool {
        guard case .asset(let id) = selection,
              let asset = assets.first(where: { $0.id == id }),
              toggleableAssetIDs.contains(asset.id) else {
            return false
        }
        toggleTrack(asset)
        return true
    }


    private var inspector: some View {
        VStack(spacing: 0) {
            inspectorTabBar

            divider

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch inspectorTab {
                    case .layout:
                        layoutInspectorContent
                    case .canvas:
                        canvasPaddingSection
                        screenAppearanceSection
                        canvasControlsSection
                    case .audio:
                        audioControlsSection
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
            .id(inspectorTab)
        }
    }

    @ViewBuilder
    private var layoutInspectorContent: some View {
        if let kind = selectedVideoLayerKind {
            frameAspectSection(kind)
            switch kind {
            case .screen:
                screenFrameSection
                screenZoomSection
            case .camera:
                cameraFrameSection
                cameraZoomSection
            }
        } else {
            sceneControlsSection
            if case .segment(let index) = selection {
                segmentSection(index: index)
            }
            screenZoomSection
        }
    }

    private var inspectorTabBar: some View {
        HStack(spacing: 0) {
            ForEach(EditorInspectorTab.allCases, id: \.self) { tab in
                Button {
                    inspectorTab = tab
                } label: {
                    VStack(spacing: 7) {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(inspectorTab == tab ? .white.opacity(0.94) : .white.opacity(0.48))
                        Rectangle()
                            .fill(inspectorTab == tab ? BlitzUI.mint : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var sceneControlsSection: some View {
        if let scene = currentEventScene, captureLayout != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    BlitzUI.sectionLabel("Scene", icon: "rectangle.3.group")
                    Spacer(minLength: 0)
                    Text(sceneEvents.count > 1 ? "Segment \(currentEventIndex + 1)" : "Full video")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                }

                LazyVGrid(columns: scenePresetColumns, spacing: 8) {
                    ForEach(
                        ScenePreset.allCases.filter { $0.supports(captureLayout ?? .horizontal) },
                        id: \.self
                    ) { preset in
                        let layout = editorLayout(for: preset)
                        BlitzScenePresetCard(
                            preset: preset,
                            layout: captureLayout ?? .horizontal,
                            isSelected: scene.sceneLayout == layout,
                            isEnabled: preset.supports(captureLayout ?? .horizontal)
                        ) {
                            applyScenePreset(preset)
                        }
                    }
                }

                Text("Drag a source to reposition it. Scene choices apply to this segment only.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var screenFrameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzUI.sectionLabel("Screen frame", icon: "macwindow")

            if sceneEvents.count > 1 {
                Text("Applies to segment \(currentEventIndex + 1)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            CameraInspectorRow(title: "Image") {
                Picker("Image", selection: segmentSceneBinding(\.screenContentMode, fallback: .fill)) {
                    ForEach(CameraContentMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .help("Fill crops the screen to the frame. Fit shows the whole recording with background around it.")
        }
    }

    @ViewBuilder
    private var screenZoomSection: some View {
        if currentEventScene?.enabledSources.contains(.screen) == true {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Source crop", systemImage: "crop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 0)
                    Text(screenZoomLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62))
                }

                HStack(spacing: 8) {
                    Slider(
                        value: screenZoomBinding,
                        in: 0...0.75,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                commitScreenZoom()
                            }
                        }
                    )
                    .controlSize(.small)
                    .tint(BlitzUI.mint)

                    Button {
                        previewScreenZoom(0)
                        commitScreenZoom()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: 7))
                    .disabled(screenZoomValue < 0.001)
                    .pointingHandCursor()
                    .help("Reset source crop")
                }
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
        }
    }

    private var scenePresetColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    private func editorLayout(for preset: ScenePreset) -> SceneLayout {
        SceneLayout.presetLayout(
            preset,
            for: captureLayout ?? .horizontal,
            screenAspectRatio: playback.sourceAspectRatios[.screen] ?? SceneLayout.defaultScreenAspectRatio,
            cameraAspectRatio: playback.sourceAspectRatios[.camera] ?? SceneLayout.cameraAspectRatio
        )
    }

    private func applyScenePreset(_ preset: ScenePreset) {
        let index = currentEventIndex
        if let correction = EditorScenePresetSourceCorrection.correction(for: preset) {
            playback.pauseForEditing()
            guard vm.applyProjectSceneCorrection(.init(eventIndex: index, correction: correction)) else {
                editErrorMessage = vm.detailMessage
                return
            }
            selection = .segment(index)
            return
        }
        let layout = editorLayout(for: preset)
        playback.pauseForEditing()
        guard vm.applyProjectSceneEdit(eventIndex: index, { scene in
            scene.sceneLayout = layout
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
        selection = .segment(index)
    }

    private var screenZoomValue: Double {
        if let screenZoomDraft {
            return screenZoomDraft
        }
        guard let scene = currentEventScene else { return 0 }
        return Double(max(scene.screenCropAmount.x, scene.screenCropAmount.y))
    }

    private var screenZoomBinding: Binding<Double> {
        Binding(
            get: { screenZoomValue },
            set: { previewScreenZoom($0) }
        )
    }

    private var screenZoomLabel: String {
        let visibleFraction = max(0.25, 1 - screenZoomValue)
        return "\(Int((100 / visibleFraction).rounded()))%"
    }

    private func previewScreenZoom(_ zoom: Double) {
        guard var scene = currentEventScene else { return }
        let clamped = min(0.75, max(0, zoom))
        if screenZoomDraft == nil {
            playback.pauseForEditing()
        }
        screenZoomDraft = clamped
        scene.screenCropAmount = CGPoint(x: clamped, y: clamped)
        playback.setPreviewSceneOverride(scene, at: playback.currentTime)
    }

    private func commitScreenZoom() {
        guard let zoom = screenZoomDraft else { return }
        let index = currentEventIndex
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) { scene in
            scene.screenCropAmount = CGPoint(x: zoom, y: zoom)
        }
        screenZoomDraft = nil
        if !succeeded {
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }

    private var cameraZoomValue: Double {
        if let cameraZoomDraft {
            return cameraZoomDraft
        }
        guard let scene = currentEventScene else { return 0 }
        return Double(max(scene.cameraCropAmount.x, scene.cameraCropAmount.y))
    }

    private var cameraZoomBinding: Binding<Double> {
        Binding(
            get: { cameraZoomValue },
            set: { previewCameraZoom($0) }
        )
    }

    private var cameraZoomLabel: String {
        let visibleFraction = max(0.25, 1 - cameraZoomValue)
        return "\(Int((100 / visibleFraction).rounded()))%"
    }

    private func previewCameraZoom(_ zoom: Double) {
        guard var scene = currentEventScene else { return }
        let clamped = min(0.75, max(0, zoom))
        if cameraZoomDraft == nil {
            playback.pauseForEditing()
        }
        cameraZoomDraft = clamped
        scene.cameraCropAmount = CGPoint(x: clamped, y: clamped)
        if clamped < 0.001 {
            scene.cameraCropPosition = .zero
        }
        playback.setPreviewSceneOverride(scene, at: playback.currentTime)
    }

    private func commitCameraZoom() {
        guard let zoom = cameraZoomDraft else { return }
        let index = currentEventIndex
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) { scene in
            scene.cameraCropAmount = CGPoint(x: zoom, y: zoom)
            if zoom < 0.001 {
                scene.cameraCropPosition = .zero
            }
        }
        cameraZoomDraft = nil
        if !succeeded {
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }

    private func setCanvasBackground(_ style: CanvasBackgroundStyle) {
        previewCanvasScene { scene in
            scene.canvasBackgroundStyle = style
        }
        scheduleCanvasSceneCommit()
        selection = .segment(currentEventIndex)
    }

    @ViewBuilder
    private var canvasPaddingSection: some View {
        if currentEventScene != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BlitzUI.sectionLabel("Padding", icon: "rectangle.inset.filled")
                    Spacer(minLength: 0)
                    Text("\(Int((canvasPaddingValue * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.64))
                }

                HStack(spacing: 8) {
                    Slider(
                        value: canvasPaddingBinding,
                        in: 0...0.12,
                        step: 0.005,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                commitCanvasPadding()
                            }
                        }
                    )
                    .controlSize(.small)
                    .tint(BlitzUI.mint)

                    Button {
                        previewCanvasPadding(0)
                        commitCanvasPadding()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: 7))
                    .disabled(canvasPaddingValue < 0.001)
                    .pointingHandCursor()
                    .help("Remove canvas padding")
                }

                Text("Adds breathing room around the video sources in this segment.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
        }
    }

    private var canvasPaddingValue: CGFloat {
        displayedCanvasScene?.canvasPadding ?? 0
    }

    private var canvasPaddingBinding: Binding<CGFloat> {
        Binding(
            get: { canvasPaddingValue },
            set: { previewCanvasPadding($0) }
        )
    }

    private func previewCanvasPadding(_ padding: CGFloat) {
        let clamped = min(0.12, max(0, padding))
        previewCanvasScene { scene in
            scene.canvasPadding = clamped
        }
    }

    private func commitCanvasPadding() {
        commitCanvasSceneDraft()
    }

    @ViewBuilder
    private var screenAppearanceSection: some View {
        if let scene = displayedCanvasScene, scene.renderedSources.contains(.screen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BlitzUI.sectionLabel("Screen", icon: "display")
                    Spacer(minLength: 0)
                    Text("\(Int((screenCornerRadiusValue * 100).rounded()))% corners")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.64))
                }

                Slider(
                    value: screenCornerRadiusBinding,
                    in: 0...0.12,
                    step: 0.005,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            commitScreenCornerRadius()
                        }
                    }
                )
                .controlSize(.small)
                .tint(BlitzUI.mint)
                .help("Round the screen recording independently of canvas padding")

                Toggle(isOn: screenShadowBinding) {
                    Label("Shadow", systemImage: "square.stack.3d.down.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(BlitzUI.mint)
                .help("Add a soft shadow under the screen recording")

                Text("Corners and shadow are independent from padding.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
        }
    }

    private var screenCornerRadiusValue: CGFloat {
        displayedCanvasScene?.screenCornerRadius ?? 0
    }

    private var screenCornerRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { screenCornerRadiusValue },
            set: { previewScreenCornerRadius($0) }
        )
    }

    private func previewScreenCornerRadius(_ radius: CGFloat) {
        let clamped = min(0.12, max(0, radius))
        previewCanvasScene { scene in
            scene.screenCornerRadius = clamped
        }
    }

    private func commitScreenCornerRadius() {
        commitCanvasSceneDraft()
    }

    private var screenShadowBinding: Binding<Bool> {
        Binding(
            get: { displayedCanvasScene?.screenShadowEnabled ?? false },
            set: { enabled in
                previewCanvasScene { scene in
                    scene.screenShadowEnabled = enabled
                }
                scheduleCanvasSceneCommit()
            }
        )
    }

    private var displayedCanvasScene: RecordingScene? {
        canvasSceneDraft ?? currentEventScene
    }

    private func previewCanvasScene(_ mutate: (inout RecordingScene) -> Void) {
        guard var scene = displayedCanvasScene else { return }
        if canvasSceneDraft == nil {
            playback.pauseForEditing()
        }
        mutate(&scene)
        canvasSceneDraft = scene
        playback.setPreviewSceneOverride(scene, at: playback.currentTime)
    }

    private func scheduleCanvasSceneCommit() {
        canvasCommitTask?.cancel()
        canvasCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            commitCanvasSceneDraft()
        }
    }

    private func commitCanvasSceneDraft() {
        canvasCommitTask?.cancel()
        canvasCommitTask = nil
        guard let draft = canvasSceneDraft else { return }
        let index = currentEventIndex
        preservesCanvasPreviewOnNextProjectRefresh = true
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) { scene in
            scene.canvasBackgroundStyle = draft.canvasBackgroundStyle
            scene.canvasPadding = draft.canvasPadding
            scene.screenCornerRadius = draft.screenCornerRadius
            scene.screenShadowEnabled = draft.screenShadowEnabled
        }
        if !succeeded {
            preservesCanvasPreviewOnNextProjectRefresh = false
            canvasSceneDraft = nil
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }

    @ViewBuilder
    private var canvasControlsSection: some View {
        if let scene = displayedCanvasScene {
            VStack(alignment: .leading, spacing: 10) {
                BlitzUI.sectionLabel("Background", icon: "paintpalette")

                LazyVGrid(columns: scenePresetColumns, spacing: 8) {
                    ForEach(CanvasBackgroundStyle.allCases, id: \.self) { style in
                        let isSelected = scene.canvasBackgroundStyle == style
                        Button {
                            setCanvasBackground(style)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                EditorCanvasBackgroundView(style: style)
                                    .frame(height: 38)
                                    .clipShape(.rect(cornerRadius: 6))
                                Text(style.displayName)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
                                    .lineLimit(1)
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .blitzSelectedSurface(isSelected: isSelected, cornerRadius: 9)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(isSelected ? BlitzUI.mint : Color.clear, lineWidth: 1.5)
                        }
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    private var audioControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzUI.sectionLabel("Audio tracks", icon: "waveform")

            backgroundMusicControl

            ForEach(assets.filter { $0.kind == .microphone || $0.kind == .systemAudio }) { asset in
                let isMuted = mutedAssetIDs.contains(asset.id)
                HStack(spacing: 10) {
                    BlitzIconTile(symbolName: asset.systemImage, isSelected: !isMuted, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.title)
                            .font(.system(size: 11.5, weight: .bold))
                        Text(isMuted ? "Muted in export" : "Included in export")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    Spacer(minLength: 0)
                    if toggleableAssetIDs.contains(asset.id) {
                        Button {
                            toggleTrack(asset)
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .background(BlitzUI.controlFill, in: .rect(cornerRadius: 7))
                        .pointingHandCursor()
                    }
                }
                .padding(10)
                .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
            }
        }
    }

    private var backgroundMusicControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BlitzIconTile(symbolName: "music.note", isSelected: backgroundMusic != nil, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backgroundMusic?.url.lastPathComponent ?? "Background music")
                        .font(.system(size: 11.5, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(backgroundMusic == nil ? "Optional" : "Loops through the full export")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                Button {
                    if backgroundMusic == nil {
                        chooseBackgroundMusic()
                    } else {
                        backgroundMusic = nil
                        backgroundMusicBookmarkData = nil
                        persistEditorState("Remove Background Music")
                    }
                } label: {
                    Image(systemName: backgroundMusic == nil ? "plus" : "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .background(BlitzUI.controlFill, in: .rect(cornerRadius: 7))
                .pointingHandCursor()
                .help(backgroundMusic == nil ? "Choose an audio file" : "Remove background music")
            }

            if backgroundMusic != nil {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.1")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                    Slider(
                        value: backgroundMusicVolumeBinding,
                        in: 0...1,
                        step: 0.01,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                persistEditorState("Change Music Volume")
                            }
                        }
                    )
                        .controlSize(.small)
                        .tint(BlitzUI.mint)
                    Text(musicVolumeLabel)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 36, alignment: .trailing)
                }

                Text("Mixed during export with a smooth fade-out.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(10)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
    }

    private var backgroundMusicVolumeBinding: Binding<Double> {
        Binding(
            get: { backgroundMusic?.volume ?? 0.18 },
            set: { volume in
                guard let selection = backgroundMusic else { return }
                backgroundMusic = ExportBackgroundMusic(
                    url: selection.url,
                    volume: min(1, max(0, volume))
                )
            }
        )
    }

    private var musicVolumeLabel: String {
        "\(Int(((backgroundMusic?.volume ?? 0) * 100).rounded()))%"
    }

    private func chooseBackgroundMusic() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Use Music"
        panel.message = "Choose background music to loop under this export."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backgroundMusic = ExportBackgroundMusic(url: url, volume: 0.18)
        backgroundMusicBookmarkData = RecordingSettingsStore.bookmarkData(for: url)
        persistEditorState("Add Background Music")
    }

    private var canDeleteSelectedCut: Bool {
        if case .segment = selection {
            return true
        }
        return false
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            BlitzUI.sectionLabel("Details", icon: "info.circle")

            VStack(alignment: .leading, spacing: 7) {
                detailRow("Name", project?.displayTitle ?? "—")
                detailRow("Saved", project?.takeDirectoryPath ?? "—", monospaced: true)
                detailRow("Resolution", resolutionLabel)
                detailRow("Ratio", ratioLabel)
                detailRow("Source FPS", "\(project?.settings.framesPerSecond ?? 0)")
                if let export = project?.exports.last {
                    detailRow("Last export", "\(export.framesPerSecond) fps · \(export.resolution)")
                }
                detailRow("Duration", timelineDuration > 0 ? formatTime(timelineDuration) : "—")
                detailRow("Sources", "\(project?.sources.filter(\.exists).count ?? 0)")
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 9))
        }
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: monospaced ? 9.5 : 11, weight: .semibold, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(monospaced ? 2 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(value)
        }
    }

    private func segmentSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            BlitzUI.sectionLabel("Segment \(index + 1)", icon: "rectangle.on.rectangle")

            if let events = project?.sceneEvents, events.indices.contains(index) {
                let event = events[index]
                let end = index + 1 < events.count ? events[index + 1].time : timelineDuration
                Text("\(formatTime(event.time)) – \(formatTime(end))")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))

                VStack(spacing: 6) {
                    ForEach(RecordingProjectSceneCorrection.allCases, id: \.self) { correction in
                        correctionButton(
                            correction,
                            isSelected: correction == selectedCorrection(for: event)
                        ) {
                            vm.applyProjectSceneCorrection(.init(eventIndex: index, correction: correction))
                        }
                    }
                }
                Text("The preview and the export both re-render with the new mix.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private func correctionButton(
        _ correction: RecordingProjectSceneCorrection,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: correction.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.56))
                    .frame(width: 16, height: 16)
                Text(correctionTitle(correction))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(BlitzUI.mint)
                }
            }
            .foregroundStyle(isSelected ? .white.opacity(0.92) : .white.opacity(0.68))
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 9)
        }
        .buttonStyle(.plain)
        .blitzSelectedSurface(isSelected: isSelected, cornerRadius: 8)
        .contentShape(.rect(cornerRadius: 8))
        .pointingHandCursor()
    }

    private func correctionTitle(_ correction: RecordingProjectSceneCorrection) -> String {
        switch correction {
        case .screenOnly: return "Screen"
        case .cameraOnly: return "Camera"
        case .screenAndCamera: return "Screen + Camera"
        }
    }

    private func selectedCorrection(for event: RecordingProject.SceneEventSnapshot) -> RecordingProjectSceneCorrection {
        let sources = Set(event.scene.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        let hasScreen = sources.contains(.screen)
        let hasCamera = sources.contains(.camera)
        switch (hasScreen, hasCamera) {
        case (true, false): return .screenOnly
        case (false, true): return .cameraOnly
        default: return .screenAndCamera
        }
    }

    private func assetSection(_ asset: EditorAsset) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            BlitzUI.sectionLabel(asset.title, icon: asset.systemImage)

            VStack(alignment: .leading, spacing: 7) {
                detailRow("File", asset.url.lastPathComponent, monospaced: true)
                detailRow("Size", asset.exists ? (library.fileSizes[asset.id] ?? "—") : "Missing")
                detailRow("Length", library.durations[asset.id].map(formatTime) ?? "—")
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 9))

            HStack(spacing: 7) {
                if toggleableAssetIDs.contains(asset.id) {
                    let isOff = hiddenAssetIDs.contains(asset.id) || mutedAssetIDs.contains(asset.id)
                    Button {
                        toggleTrack(asset)
                    } label: {
                        Label(
                            asset.isVideo ? (isOff ? "Show" : "Hide") : (isOff ? "Unmute" : "Mute"),
                            systemImage: asset.isVideo
                                ? (isOff ? "eye" : "eye.slash")
                                : (isOff ? "speaker.wave.2" : "speaker.slash")
                        )
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
                }
                if asset.exists {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
                }
            }

            if asset.kind == .camera, currentEventScene != nil {
                cameraFrameSection
            }
        }
    }

    @ViewBuilder
    private var cameraFrameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzUI.sectionLabel("Camera frame", icon: "video")

            if sceneEvents.count > 1 {
                Text("Applies to segment \(currentEventIndex + 1)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            CameraInspectorRow(title: "Image") {
                Picker("Image", selection: segmentSceneBinding(\.cameraContentMode, fallback: .fill)) {
                    ForEach(CameraContentMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .help("Fill the frame edge to edge, or fit the whole camera image")

            Toggle(isOn: segmentSceneBinding(\.cameraShadowEnabled, fallback: false)) {
                Label("Shadow", systemImage: "square.stack.3d.down.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(BlitzUI.mint)
            .help("Add a soft shadow under the camera")

            Text("Drag the camera in the canvas to move it; drag a corner to resize.")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    @ViewBuilder
    private var cameraZoomSection: some View {
        if currentEventScene?.enabledSources.contains(.camera) == true {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label("Source crop", systemImage: "crop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 0)
                    Text(cameraZoomLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62))
                }

                HStack(spacing: 8) {
                    Slider(
                        value: cameraZoomBinding,
                        in: 0...0.75,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                commitCameraZoom()
                            }
                        }
                    )
                    .controlSize(.small)
                    .tint(BlitzUI.mint)

                    Button {
                        previewCameraZoom(0)
                        commitCameraZoom()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: 7))
                    .disabled(cameraZoomValue < 0.001)
                    .pointingHandCursor()
                    .help("Reset camera source crop")
                }
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func frameAspectSection(_ kind: SceneLayerKind) -> some View {
        if let scene = currentEventScene {
            let sceneRequest = EditorFrameRatioSceneRequest(kind: kind, scene: scene)
            let currentRatio = frameDisplayAspectRatio(sceneRequest)
            let selectedPreset = selectedFrameRatioPreset(sceneRequest)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BlitzUI.sectionLabel("Frame", icon: "aspectratio")
                    Spacer(minLength: 0)
                    Text(EditorFrameRatioLabel.text(for: currentRatio))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(BlitzUI.mint)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(BlitzUI.mint.opacity(0.10), in: .capsule)
                }

                LazyVGrid(columns: frameRatioColumns, spacing: 6) {
                    ForEach(availableFrameRatioPresets(for: kind)) { preset in
                        let isSelected = preset == selectedPreset
                        EditorFrameRatioButton(
                            title: preset.title,
                            isSelected: isSelected
                        ) {
                            applyFrameRatio(.init(kind: kind, preset: preset))
                        }
                    }
                }

                Toggle("Lock aspect ratio", isOn: aspectRatioLockBinding(for: kind))
                    .font(.system(size: 10.5, weight: .semibold))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(BlitzUI.mint)

                Text("Lock for proportional corners. Unlock or drag a side handle to reshape.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
        }
    }

    private var frameRatioColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible())]
    }

    private func aspectRatioLockBinding(for kind: SceneLayerKind) -> Binding<Bool> {
        Binding(
            get: { aspectRatioLockedKinds.contains(kind) },
            set: { isLocked in
                if isLocked {
                    aspectRatioLockedKinds.insert(kind)
                } else {
                    aspectRatioLockedKinds.remove(kind)
                }
            }
        )
    }

    private func availableFrameRatioPresets(for kind: SceneLayerKind) -> [EditorFrameRatioPreset] {
        let sourceRatio = playback.sourceAspectRatios[kind] ?? 1
        return EditorFrameRatioPreset.allCases.filter { preset in
            preset == .source || abs(preset.aspectRatio(sourceRatio: sourceRatio) - sourceRatio) > 0.01
        }
    }

    private func frameDisplayAspectRatio(_ request: EditorFrameRatioSceneRequest) -> CGFloat {
        let frame = layoutFrame(request.kind, in: request.scene.sceneLayout)
        guard frame.height > 0 else { return 1 }
        return frame.width / frame.height * canvasAspectRatio
    }

    private func selectedFrameRatioPreset(_ request: EditorFrameRatioSceneRequest) -> EditorFrameRatioPreset? {
        let currentRatio = frameDisplayAspectRatio(request)
        let sourceRatio = playback.sourceAspectRatios[request.kind] ?? 1
        return availableFrameRatioPresets(for: request.kind).first { preset in
            abs(preset.aspectRatio(sourceRatio: sourceRatio) - currentRatio) < 0.02
        }
    }

    private func applyFrameRatio(_ request: EditorFrameRatioChange) {
        guard var scene = currentEventScene else { return }
        let sourceRatio = playback.sourceAspectRatios[request.kind] ?? 1
        let displayRatio = request.preset.aspectRatio(sourceRatio: sourceRatio)
        let normalizedRatio = displayRatio / canvasAspectRatio
        let frame = layoutFrame(request.kind, in: scene.sceneLayout)
        let resized = SceneLayerResizing.settingAspectRatio(.init(
            frame: frame,
            aspectRatio: normalizedRatio
        ))
        setLayoutFrame(resized, kind: request.kind, in: &scene.sceneLayout)
        if request.kind == .camera {
            scene.cameraContentMode = .fill
        }

        playback.pauseForEditing()
        guard vm.applyProjectSceneEdit(eventIndex: currentEventIndex, { editedScene in
            editedScene.sceneLayout = scene.sceneLayout
            editedScene.cameraContentMode = scene.cameraContentMode
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private func segmentSceneBinding<Value>(
        _ keyPath: WritableKeyPath<RecordingScene, Value>,
        fallback: Value
    ) -> Binding<Value> {
        let index = currentEventIndex
        let value = currentEventScene?[keyPath: keyPath] ?? fallback
        return Binding(
            get: { value },
            set: { newValue in
                vm.applyProjectSceneEdit(eventIndex: index) { $0[keyPath: keyPath] = newValue }
            }
        )
    }


    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private var divider: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(height: 1)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(width: 1)
    }
}

struct EditorFrameRatioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.68))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    isSelected ? BlitzUI.selectedFill : BlitzUI.quietFill,
                    in: .rect(cornerRadius: 7)
                )
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

private struct EditorLayoutDraft {
    let eventIndex: Int
    let startLayout: SceneLayout
    let startCameraContentMode: CameraContentMode
    var scene: RecordingScene
}

private enum EditorFrameRatioPreset: String, CaseIterable, Identifiable {
    case source
    case landscape
    case classic
    case square
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .landscape: return "16:9"
        case .classic: return "4:3"
        case .square: return "1:1"
        case .portrait: return "9:16"
        }
    }

    func aspectRatio(sourceRatio: CGFloat) -> CGFloat {
        switch self {
        case .source: return sourceRatio
        case .landscape: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        case .square: return 1
        case .portrait: return 9.0 / 16.0
        }
    }
}

private struct EditorFrameRatioChange {
    let kind: SceneLayerKind
    let preset: EditorFrameRatioPreset
}

private struct EditorFrameRatioSceneRequest {
    let kind: SceneLayerKind
    let scene: RecordingScene
}

private enum EditorFrameRatioLabel {
    static func text(for ratio: CGFloat) -> String {
        let commonRatios: [(value: CGFloat, label: String)] = [
            (16.0 / 9.0, "16:9"),
            (16.0 / 10.0, "16:10"),
            (3.0 / 2.0, "3:2"),
            (4.0 / 3.0, "4:3"),
            (1, "1:1"),
            (9.0 / 16.0, "9:16")
        ]
        if let match = commonRatios.first(where: { abs($0.value - ratio) < 0.02 }) {
            return match.label
        }
        return String(format: "%.2f:1", ratio)
    }
}

private struct EditorCanvasLayer: Identifiable {
    let kind: SceneLayerKind
    let assetID: String?
    let frame: CGRect      // normalized 0...1, top-left origin
    let displayAspectRatio: CGFloat
    let isAspectRatioLocked: Bool
    let isSelected: Bool
    let isEditable: Bool

    var id: String { kind.rawValue }
}

private let editorCanvasSpace = "EditorCanvasOverlay"

private struct EditorCanvasLayerOverlay: View {
    let layers: [EditorCanvasLayer]
    let onSelect: (EditorCanvasLayer) -> Void
    let onMove: (SceneLayerKind, CGSize, Bool) -> Void
    let onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void
    @State private var hoveredLayerID: String?

    var body: some View {
        GeometryReader { proxy in
            ForEach(layers) { layer in
                EditorCanvasLayerView(
                    layer: layer,
                    isHovering: hoveredLayerID == layer.id
                )
                .frame(
                    width: layer.frame.width * proxy.size.width,
                    height: layer.frame.height * proxy.size.height
                )
                .offset(
                    x: layer.frame.minX * proxy.size.width,
                    y: layer.frame.minY * proxy.size.height
                )
                .allowsHitTesting(false)
            }

            EditorCanvasInteractionView(
                layers: layers,
                hoveredLayerID: $hoveredLayerID,
                onSelect: onSelect,
                onMove: { kind, translation, ended in
                    onMove(kind, normalized(translation, in: proxy.size), ended)
                },
                onResize: { kind, anchor, translation, ended in
                    onResize(kind, anchor, normalized(translation, in: proxy.size), ended)
                }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .coordinateSpace(name: editorCanvasSpace)
    }

    private func normalized(_ translation: CGSize, in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGSize(width: translation.width / size.width, height: translation.height / size.height)
    }
}

private struct EditorCanvasSourcePreviewOverlay: View {
    let scene: RecordingScene
    let assetsByID: [String: EditorAsset]
    let previewImages: [String: CGImage]
    let library: EditorMediaLibrary

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGRect(origin: .zero, size: proxy.size)
            let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)

            EditorCanvasBackgroundView(style: scene.canvasBackgroundStyle)
                .frame(width: proxy.size.width, height: proxy.size.height)

            ForEach(geometry.activeLayerOrder, id: \.self) { kind in
                if let asset = asset(for: kind), let image = image(for: asset) {
                    sourceView(kind: kind, image: image, geometry: geometry)
                }
            }
        }
    }

    private func asset(for kind: SceneLayerKind) -> EditorAsset? {
        switch kind {
        case .screen:
            return assetsByID.values.first { $0.kind == .screen }
        case .camera:
            return assetsByID.values.first { $0.kind == .camera }
        }
    }

    private func image(for asset: EditorAsset) -> CGImage? {
        previewImages[asset.id] ?? library.posters[asset.id]
    }

    private func sourceView(kind: SceneLayerKind, image: CGImage, geometry: SceneRenderGeometry) -> some View {
        let placement = geometry.videoPlacement(for: kind)
        let target = placement.targetRect
        let aspectRatio = CGFloat(image.width) / max(1, CGFloat(image.height))
        let sourceFrame = placement.sourceFrame(sourceAspectRatio: aspectRatio)
        let radius = geometry.sourceCornerRadius(for: kind)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: sourceFrame.width, height: sourceFrame.height)
                .offset(x: sourceFrame.minX - target.minX, y: sourceFrame.minY - target.minY)
        }
        .frame(width: target.width, height: target.height, alignment: .topLeading)
        .clipShape(shape)
        .shadow(
            color: sourceShadowEnabled(for: kind) ? .black.opacity(0.38) : .clear,
            radius: sourceShadowEnabled(for: kind) ? min(18, max(5, min(target.width, target.height) * 0.04)) : 0,
            y: sourceShadowEnabled(for: kind) ? 5 : 0
        )
        .offset(x: target.minX, y: target.minY)
    }

    private func sourceShadowEnabled(for kind: SceneLayerKind) -> Bool {
        switch kind {
        case .screen:
            return scene.screenShadowEnabled
        case .camera:
            return scene.cameraShadowEnabled
        }
    }
}

private struct EditorCanvasBackgroundView: View {
    let style: CanvasBackgroundStyle

    var body: some View {
        Color(cgColor: style.appearance.solidCGColor)
    }
}

private struct EditorCanvasLayerView: View {
    let layer: EditorCanvasLayer
    let isHovering: Bool

    var body: some View {
        ZStack {
            if layer.isSelected {
                Rectangle()
                    .stroke(BlitzUI.mint, lineWidth: 1.5)
            } else if isHovering {
                Rectangle()
                    .stroke(BlitzUI.mint.opacity(0.82), lineWidth: 1.25)
            }
        }
        .overlay {
            if layer.isSelected && layer.isEditable {
                resizeHandles
            }
        }
        .overlay(alignment: .top) {
            if layer.isSelected && layer.isEditable {
                Label(
                    EditorFrameRatioLabel.text(for: layer.displayAspectRatio),
                    systemImage: layer.isAspectRatioLocked ? "lock.fill" : "lock.open.fill"
                )
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.black.opacity(0.78), in: .capsule)
                    .padding(.top, 8)
            }
        }
    }

    private var resizeHandles: some View {
        ZStack {
            handle(.topLeft, alignment: .topLeading)
            handle(.topRight, alignment: .topTrailing)
            handle(.bottomLeft, alignment: .bottomLeading)
            handle(.bottomRight, alignment: .bottomTrailing)
            horizontalEdgeHandle(alignment: .top)
            horizontalEdgeHandle(alignment: .bottom)
            verticalEdgeHandle(alignment: .leading)
            verticalEdgeHandle(alignment: .trailing)
        }
    }

    private func horizontalEdgeHandle(alignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(BlitzUI.mint)
            .frame(width: 24, height: 6)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.black.opacity(0.9), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(y: alignment.vertical == .top ? -3 : 3)
    }

    private func verticalEdgeHandle(alignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(BlitzUI.mint)
            .frame(width: 6, height: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.black.opacity(0.9), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(x: alignment.horizontal == .leading ? -3 : 3)
    }

    private func handle(_ anchor: ResizeAnchor, alignment: Alignment) -> some View {
        let offsetX: CGFloat = alignment.horizontal == .leading ? -6 : 6
        let offsetY: CGFloat = alignment.vertical == .top ? -6 : 6
        return Rectangle()
            .fill(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: alignment) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(BlitzUI.mint)
                    .frame(width: 12, height: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.9), lineWidth: 1)
                    }
                    .padding(2)
                    .offset(x: offsetX, y: offsetY)
            }
    }
}

private struct EditorCanvasInteractionView: NSViewRepresentable {
    let layers: [EditorCanvasLayer]
    @Binding var hoveredLayerID: String?
    let onSelect: (EditorCanvasLayer) -> Void
    let onMove: (SceneLayerKind, CGSize, Bool) -> Void
    let onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.layers = layers
        view.hoveredLayerID = hoveredLayerID
        view.onHover = { hoveredLayerID = $0 }
        view.onSelect = onSelect
        view.onMove = onMove
        view.onResize = onResize
        view.needsDisplay = true
    }

    final class InteractionView: NSView {
        enum DragMode {
            case move(SceneLayerKind)
            case resize(SceneLayerKind, ResizeAnchor)
        }

        var layers: [EditorCanvasLayer] = []
        var hoveredLayerID: String?
        var onHover: ((String?) -> Void)?
        var onSelect: ((EditorCanvasLayer) -> Void)?
        var onMove: ((SceneLayerKind, CGSize, Bool) -> Void)?
        var onResize: ((SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragMode: DragMode?
        private var dragStart: CGPoint = .zero

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
            trackingArea = area
            addTrackingArea(area)
        }

        override func mouseMoved(with event: NSEvent) {
            guard dragMode == nil else { return }
            let point = convert(event.locationInWindow, from: nil)
            setHoveredLayer(resizeHit(at: point)?.layer.id ?? hitLayer(at: point)?.id)
            cursor(at: point).set()
        }

        override func mouseExited(with event: NSEvent) {
            guard dragMode == nil else { return }
            setHoveredLayer(nil)
            NSCursor.arrow.set()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            dragStart = point
            if let hit = resizeHit(at: point) {
                onSelect?(hit.layer)
                setHoveredLayer(hit.layer.id)
                dragMode = .resize(hit.layer.kind, hit.anchor)
                hit.anchor.cursor.set()
                return
            }
            guard let layer = hitLayer(at: point) else {
                dragMode = nil
                setHoveredLayer(nil)
                return
            }
            onSelect?(layer)
            setHoveredLayer(layer.id)
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                dragMode = .resize(layer.kind, anchor)
                anchor.cursor.set()
            } else if layer.isEditable {
                dragMode = .move(layer.kind)
                NSCursor.closedHand.set()
            } else {
                dragMode = nil
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragMode else { return }
            let point = convert(event.locationInWindow, from: nil)
            let translation = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            switch dragMode {
            case .move(let kind):
                onMove?(kind, translation, false)
            case .resize(let kind, let anchor):
                onResize?(kind, anchor, translation, false)
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let dragMode else { return }
            let point = convert(event.locationInWindow, from: nil)
            let translation = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            switch dragMode {
            case .move(let kind):
                onMove?(kind, translation, true)
            case .resize(let kind, let anchor):
                onResize?(kind, anchor, translation, true)
            }
            self.dragMode = nil
            cursor(at: point).set()
        }

        private func hitLayer(at point: CGPoint) -> EditorCanvasLayer? {
            layers.reversed().first { frame(for: $0).contains(point) }
        }

        private func resizeHit(at point: CGPoint) -> (layer: EditorCanvasLayer, anchor: ResizeAnchor)? {
            for layer in layers.reversed() where layer.isSelected && layer.isEditable {
                if let anchor = resizeAnchor(at: point, in: layer) {
                    return (layer, anchor)
                }
            }
            return nil
        }

        private func frame(for layer: EditorCanvasLayer) -> CGRect {
            CGRect(
                x: layer.frame.minX * bounds.width,
                y: layer.frame.minY * bounds.height,
                width: layer.frame.width * bounds.width,
                height: layer.frame.height * bounds.height
            )
        }

        private func resizeAnchor(at point: CGPoint, in layer: EditorCanvasLayer) -> ResizeAnchor? {
            let frame = frame(for: layer)
            let size: CGFloat = 18
            let half = size / 2
            let cornerHandles: [(ResizeAnchor, CGRect)] = [
                (.topLeft, CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size)),
                (.topRight, CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)),
                (.bottomLeft, CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size)),
                (.bottomRight, CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size))
            ]
            if let corner = cornerHandles.first(where: { $0.1.contains(point) }) {
                return corner.0
            }

            let edgeThickness: CGFloat = 16
            let edgeHalf = edgeThickness / 2
            let edgeHandles: [(ResizeAnchor, CGRect)] = [
                (.top, CGRect(
                    x: frame.minX + half,
                    y: frame.minY - edgeHalf,
                    width: max(0, frame.width - size),
                    height: edgeThickness
                )),
                (.right, CGRect(
                    x: frame.maxX - edgeHalf,
                    y: frame.minY + half,
                    width: edgeThickness,
                    height: max(0, frame.height - size)
                )),
                (.bottom, CGRect(
                    x: frame.minX + half,
                    y: frame.maxY - edgeHalf,
                    width: max(0, frame.width - size),
                    height: edgeThickness
                )),
                (.left, CGRect(
                    x: frame.minX - edgeHalf,
                    y: frame.minY + half,
                    width: edgeThickness,
                    height: max(0, frame.height - size)
                ))
            ]
            return edgeHandles.first { $0.1.contains(point) }?.0
        }

        private func cursor(at point: CGPoint) -> NSCursor {
            if let hit = resizeHit(at: point) {
                return hit.anchor.cursor
            }
            guard let layer = hitLayer(at: point) else { return .arrow }
            if layer.isSelected, layer.isEditable, let anchor = resizeAnchor(at: point, in: layer) {
                return anchor.cursor
            }
            return layer.isEditable ? .openHand : .pointingHand
        }

        private func setHoveredLayer(_ id: String?) {
            guard hoveredLayerID != id else { return }
            hoveredLayerID = id
            onHover?(id)
        }
    }
}

private struct EditorWaveformBadge: View {
    let samples: [Float]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let values = samples.isEmpty ? Array(repeating: Float(0.25), count: 48) : samples
            let barCount = min(values.count, 64)
            let stride = max(1, values.count / barCount)
            let slot = size.width / CGFloat(barCount)
            let barWidth = max(1, slot - 1)
            let centerY = size.height / 2
            for index in 0..<barCount {
                let value = CGFloat(values[min(index * stride, values.count - 1)])
                let height = max(1.5, value * size.height)
                let rect = CGRect(x: CGFloat(index) * slot, y: centerY - height / 2, width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(tint.opacity(samples.isEmpty ? 0.3 : 0.85))
                )
            }
        }
    }
}

private struct EditorPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let redrawID: Int

    func makeNSView(context: Context) -> EditorPlayerLayerHostView {
        let view = EditorPlayerLayerHostView()
        view.player = player
        view.redrawID = redrawID
        return view
    }

    func updateNSView(_ nsView: EditorPlayerLayerHostView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        if nsView.redrawID != redrawID {
            nsView.redrawID = redrawID
            nsView.invalidateFallbackFrame()
        }
    }

    static func dismantleNSView(_ nsView: EditorPlayerLayerHostView, coordinator: ()) {
        nsView.player = nil
    }
}

private final class EditorPlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let fallbackLayer = CALayer()
    private let ciContext = CIContext()
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var attachedFallbackItem: AVPlayerItem?
    private var currentItemObservation: NSKeyValueObservation?
    private var videoCompositionObservation: NSKeyValueObservation?
    private var fallbackTimer: Timer?
    private var fallbackImageTask: Task<Void, Never>?
    private var fallbackNeedsRerender = false
    private var fallbackGeneration = 0
    private var fallbackImageTime: CMTime?
    var redrawID = 0

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            guard playerLayer.player !== newValue else { return }
            currentItemObservation = nil
            playerLayer.player = newValue
            attachFallbackOutput(to: newValue?.currentItem)
            currentItemObservation = newValue?.observe(\.currentItem, options: [.new]) { [weak self] _, change in
                Task { @MainActor in
                    self?.attachFallbackOutput(to: change.newValue ?? nil)
                }
            }
            updateFallbackTimer()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        fallbackLayer.contentsGravity = .resizeAspect
        fallbackLayer.backgroundColor = NSColor.black.cgColor
        fallbackLayer.isHidden = true
        playerLayer.addSublayer(fallbackLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { false }

    override func makeBackingLayer() -> CALayer {
        playerLayer
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.frame = bounds
        CATransaction.commit()
    }

    deinit {
        fallbackTimer?.invalidate()
        fallbackImageTask?.cancel()
    }

    private func attachFallbackOutput(to item: AVPlayerItem?) {
        fallbackGeneration += 1
        fallbackImageTask?.cancel()
        fallbackImageTask = nil
        fallbackNeedsRerender = false
        fallbackImageTime = nil
        videoCompositionObservation = nil
        if let videoOutput {
            attachedFallbackItem?.remove(videoOutput)
        }
        attachedFallbackItem = nil
        guard let item else {
            videoOutput = nil
            fallbackLayer.contents = nil
            fallbackLayer.isHidden = true
            updateFallbackTimer()
            return
        }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        attachedFallbackItem = item
        videoCompositionObservation = item.observe(\.videoComposition, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.invalidateFallbackFrame()
            }
        }
        updateFallbackTimer()
        renderFallbackFrame()
    }

    func invalidateFallbackFrame() {
        fallbackGeneration += 1
        fallbackImageTask?.cancel()
        fallbackImageTask = nil
        fallbackNeedsRerender = false
        fallbackImageTime = nil
        renderFallbackFrame()
    }

    private func updateFallbackTimer() {
        fallbackTimer?.invalidate()
        guard playerLayer.player != nil else {
            fallbackTimer = nil
            return
        }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.renderFallbackFrame()
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func renderFallbackFrame() {
        guard let player = playerLayer.player,
              let output = videoOutput else { return }
        let itemTime = player.rate != 0
            ? output.itemTime(forHostTime: CACurrentMediaTime())
            : player.currentTime()
        let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        switch EditorFallbackFramePolicy.decision(isPlaying: player.rate != 0, hasPixelBuffer: pixelBuffer != nil) {
        case .renderPixelBuffer:
            break
        case .renderStillFrame:
            renderFallbackStillFrame(from: player.currentItem, at: itemTime)
            return
        case .hideFallback:
            fallbackLayer.isHidden = true
            return
        }
        guard let pixelBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        fallbackLayer.contents = cgImage
        fallbackLayer.isHidden = false
    }

    private func renderFallbackStillFrame(from item: AVPlayerItem?, at time: CMTime) {
        guard let item else { return }
        guard fallbackImageTask == nil else {
            fallbackNeedsRerender = true
            return
        }
        let requestedTime = time.seconds.isFinite && time.seconds >= 0 ? time : .zero
        if let fallbackImageTime,
           fallbackLayer.contents != nil,
           abs(fallbackImageTime.seconds - requestedTime.seconds) < 0.03 {
            return
        }
        fallbackImageTime = requestedTime
        let generation = fallbackGeneration
        let asset = item.asset
        let videoComposition = item.videoComposition
        fallbackImageTask = Task { [weak self] in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.videoComposition = videoComposition
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
            let image = try? await generator.image(at: requestedTime).image
            await MainActor.run {
                guard let self else { return }
                self.fallbackImageTask = nil
                if generation == self.fallbackGeneration, let image {
                    self.fallbackLayer.contents = image
                    self.fallbackLayer.isHidden = false
                }
                if self.fallbackNeedsRerender {
                    self.fallbackNeedsRerender = false
                    self.fallbackImageTime = nil
                    self.renderFallbackFrame()
                }
            }
        }
    }
}

enum EditorFallbackFrameDecision: Equatable {
    case renderPixelBuffer
    case renderStillFrame
    case hideFallback
}

enum EditorFallbackFramePolicy {
    static func decision(isPlaying: Bool, hasPixelBuffer: Bool) -> EditorFallbackFrameDecision {
        if hasPixelBuffer {
            return .renderPixelBuffer
        }
        if isPlaying {
            return .hideFallback
        }
        return .renderStillFrame
    }
}

private struct EditorKeyboardShortcutView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ShortcutView {
        let view = ShortcutView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: ShortcutView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    final class ShortcutView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installKeyMonitorIfNeeded()
        }

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        private func installKeyMonitorIfNeeded() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else {
                    return event
                }
                return self.onKeyDown?(event) == true ? nil : event
            }
        }
    }
}
