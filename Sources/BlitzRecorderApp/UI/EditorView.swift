import AppKit
import AVFoundation
import CoreImage
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers


private enum EditorInspectorTab: String, CaseIterable {
    case layout = "Layout"
    case audio = "Audio"
    case text = "Text"
    case zoom = "Motion"
    case silence = "Silence"
    case blitzReels = "BlitzReels"

    var systemImage: String {
        switch self {
        case .layout: return BlitzSymbols.layout
        case .audio: return "waveform"
        case .text: return "textformat"
        case .zoom: return "cursorarrow.motionlines"
        case .silence: return "waveform.path"
        case .blitzReels: return "arrow.up.right"
        }
    }
}

private struct EditorExportPresetRequest {
    let preset: ExportPerformancePreset
    let project: RecordingProject
}

private enum EditorCameraInsetControlChange {
    case alignment(CameraInsetAlignment)
    case shape(CameraInsetShape)
    case size(CGFloat)
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
    @State private var timelineZoom: Double = 1
    @State private var showsTimelineShortcuts = false
    @State private var pendingRangeCutSeek: Double?
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
    @State private var cameraCropDraft: EditorCameraCropDraft?
    @State private var canvasSceneDraft: RecordingScene?
    @State private var canvasCommitTask: Task<Void, Never>?
    @State private var preservesCanvasPreviewOnNextProjectRefresh = false
    @State private var editErrorMessage: String?
    @State private var silence = SilenceEditingSession()
    @State private var inspectorTab: EditorInspectorTab = .layout
    @State private var showsSourceFraming = false
    @State private var framingSource: SceneLayerKind = .screen
    @State private var aspectRatioLockedKinds: Set<SceneLayerKind> = [.screen, .camera]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

            if let exportStatus {
                EditorExportStatusView(configuration: .init(
                    status: exportStatus,
                    open: { NSWorkspace.shared.open($0) },
                    reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                    retry: exportVideo,
                    dismiss: {
                        vm.lastExportSucceededURL = nil
                        vm.lastExportError = nil
                    }
                ))
            }

            divider

            EditorWorkspaceSplitView {
                playerColumn
                    .background(BlitzUI.canvasBackground)
            } inspector: {
                inspector
                    .background(BlitzUI.panelBackground)
            } timeline: {
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
                playbackVolume: Binding(
                    get: { playback.playbackVolume },
                    set: { playback.setPlaybackVolume($0) }
                ),
                hasPlaybackAudio: !playback.muteableSources.isEmpty,
                onTogglePlaybackMute: { playback.togglePlaybackMute() },
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
                onDeleteSegment: deleteSelectedSegment,
                canDeleteSegment: canDeleteSelectedSegment,
                onJoinSegment: joinSelectedSegment,
                onCutRange: cutSelectedRange,
                onRestoreRange: restoreSelectedRange,
                onMarkIn: markRangeIn,
                onMarkOut: markRangeOut,
                zoomLevel: $timelineZoom,
                showsShortcuts: $showsTimelineShortcuts,
                silence: silence,
                isEditingSilence: inspectorTab == .silence,
                onOpenSilence: openSilenceInspector
            )
            }
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
                if let time = pendingRangeCutSeek {
                    pendingRangeCutSeek = nil
                    playback.seek(to: time)
                }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                layoutDraft = nil
                screenZoomDraft = nil
                cameraZoomDraft = nil
                cameraCropDraft = nil
                canvasSceneDraft = nil
            }
            reloadTask = task
        }
        .onDisappear {
            silence.cancel()
            reloadTask?.cancel()
            reloadTask = nil
            canvasCommitTask?.cancel()
            canvasCommitTask = nil
            playback.teardown()
        }
        .onChange(of: selection) { _, selection in
            guard [.layout, .audio].contains(inspectorTab) else { return }
            switch selection {
            case .segment:
                inspectorTab = .layout
            case .asset(let id):
                if let source = selectedVideoLayerKind {
                    framingSource = source
                    showsSourceFraming = true
                }
                let kind = assets.first(where: { $0.id == id })?.kind
                inspectorTab = kind == .microphone || kind == .systemAudio
                    ? .audio
                    : .layout
            case .range, .silenceRange, .silenceRanges:
                break
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
        guard !Task.isCancelled else { return }
        silence.prepare(.init(vm: vm, playback: playback, project: project))
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
            silence.prepare(.init(vm: vm, playback: playback, project: project))
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
            .buttonStyle(BlitzPressButtonStyle())
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

            BlitzToolbarButton(configuration: .init(
                title: "Settings",
                symbolName: "gearshape",
                showsTitle: false,
                action: { vm.onPresentSettings?(nil) }
            ))
            .help("Open Settings (Cmd+,)")
            .padding(.trailing, 12)

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
            Label(
                vm.state == .finishing ? "Exporting" : "Export",
                systemImage: vm.state == .finishing ? "hourglass" : "square.and.arrow.up"
            )
        }
        .blitzButton(.accent)
        .controlSize(.large)
        .disabled(project == nil || vm.state != .idle)
        .help("Choose export settings")
        .popover(isPresented: $isExportPopoverPresented, arrowEdge: .top) {
            exportPopover
        }
    }

    private var exportPopover: some View {
        EditorExportPopover(configuration: .init(
            preset: Binding(
                get: { selectedExportPreset },
                set: { preset in
                    guard let project else { return }
                    applyExportPreset(EditorExportPresetRequest(preset: preset, project: project))
                    persistEditorState("Change Export Preset")
                }
            ),
            format: Binding(
                get: { selectedFormat },
                set: {
                    selectedFormat = $0
                    persistEditorState("Change Export Format")
                }
            ),
            resolution: Binding(
                get: { selectedResolution },
                set: {
                    selectedResolution = $0
                    selectedExportPreset = .custom
                    persistEditorState("Change Export Resolution")
                }
            ),
            framesPerSecond: Binding(
                get: { selectedExportFramesPerSecond },
                set: {
                    selectedExportFramesPerSecond = $0
                    selectedExportPreset = .custom
                    persistEditorState("Change Export Frame Rate")
                }
            ),
            quality: Binding(
                get: { selectedExportQuality },
                set: {
                    selectedExportQuality = $0
                    selectedExportPreset = .custom
                    persistEditorState("Change Export Quality")
                }
            ),
            summary: exportSummary,
            estimatedSize: exportEstimatedSize,
            encodingDetail: String(format: "HEVC · %.1f Mbps", Double(exportBitrate) / 1_000_000),
            directory: vm.settings.outputDirectory,
            musicSummary: backgroundMusic.map { "\($0.url.lastPathComponent) · \(musicVolumeLabel)" },
            canExport: project != nil && vm.state == .idle,
            export: exportVideo,
            showFolder: { NSWorkspace.shared.open(vm.settings.outputDirectory) },
            showBlitzReels: {
                isExportPopoverPresented = false
                inspectorTab = .blitzReels
            }
        ))
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
        return "\(dimensions.width) × \(dimensions.height) · \(exportFrameRate) fps"
    }

    private var exportEstimatedSize: String {
        let estimatedBytes = Int64(max(0, timelineDuration) * Double(exportBitrate + 192_000) / 8)
        return "≈ " + ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
    }

    private func exportVideo() {
        let profile = exportPerformanceProfile
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

    private var exportStatus: EditorExportStatus? {
        if vm.state == .finishing {
            return .exporting(.init(
                title: vm.sessionProgressTitle,
                percentage: vm.sessionProgressLabel,
                detail: vm.sessionProgressDetail,
                value: vm.sessionProgressValue
            ))
        }
        if let error = vm.lastExportError { return .failed(error) }
        if let url = vm.lastExportSucceededURL { return .succeeded(url) }
        return nil
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
                    previewSceneRevision: playback.previewSceneRevision,
                    cameraCropEditingScene: cameraCropDraft?.scene
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 12))
                    .allowsHitTesting(false)
            }

            if playback.isReady, let cameraCropDraft,
               let sourceAspectRatio = playback.sourceAspectRatios[.camera] {
                EditorCameraCropOverlay(configuration: .init(
                    scene: cameraCropDraft.scene,
                    renderSize: playback.renderSize,
                    sourceAspectRatio: sourceAspectRatio,
                    onChange: updateEditorCameraCrop,
                    onDone: applyEditorCameraCrop,
                    onReset: resetEditorCameraCrop,
                    onCancel: cancelEditorCameraCrop
                ))
            } else if playback.isReady {
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
        let draftScene = layoutDraft?.scene ?? canvasSceneDraft
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
        guard !vm.isShowingSettings, !isExportPopoverPresented,
            !showsTimelineShortcuts, vm.state != .finishing,
            let command = EditorKeyboardCommand.resolve(.init(
                keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                modifiers: event.modifierFlags
            ))
        else { return false }
        if command == .showHelp {
            showsTimelineShortcuts = true
            return true
        }
        guard playback.isReady else { return false }
        switch command {
        case .togglePlayback: playback.togglePlayback()
        case .pause: playback.pauseForEditing()
        case .playForward: playback.playForwardOrIncreaseRate()
        case .seek(let seconds): playback.seek(by: seconds)
        case .step(let frames): playback.step(byFrames: frames)
        case .goToStart: playback.seek(to: 0)
        case .goToEnd: playback.seek(to: timelineDuration)
        case .previousBoundary: playback.seek(to: previousBoundary())
        case .nextBoundary: playback.seek(to: nextBoundary())
        case .split: splitAtPlayhead()
        case .deleteSelection:
            if let selected = selection?.silenceSelection { silence.toggleRanges(selected.ranges) }
            else if inspectorTab == .silence, let range = selection?.timeRange {
                selection = .silenceRange(range)
                silence.toggle(range)
            }
            else if case .range = selection { cutSelectedRange() }
            else if case .segment = selection { deleteSelectedSegment() }
            else { return false }
        case .restoreSelection: restoreSelectedRange()
        case .toggleTrack: return toggleSelectedAsset()
        case .markIn: markRangeIn()
        case .markOut: markRangeOut()
        case .clearSelection: selection = nil
        case .zoomIn:
            timelineZoom = EditorTimelineZoom.clamp(.init(value: timelineZoom * 1.5, duration: timelineDuration))
        case .zoomOut:
            timelineZoom = EditorTimelineZoom.clamp(.init(value: timelineZoom / 1.5, duration: timelineDuration))
        case .fit: timelineZoom = 1
        case .showHelp: return false
        }
        return true
    }

    private func markRangeIn() {
        guard playback.isReady else { return }
        let time = playback.currentTime
        let end: Double
        if let range = selection?.timeRange { end = max(time, range.end) }
        else { end = timelineDuration }
        if let range = EditorTimeRange.resolve(.init(anchor: time, head: end, duration: timelineDuration)) {
            selection = .range(range)
        }
    }

    private func markRangeOut() {
        guard playback.isReady else { return }
        let time = playback.currentTime
        let start: Double
        if let range = selection?.timeRange { start = min(time, range.start) }
        else { start = 0 }
        if let range = EditorTimeRange.resolve(.init(anchor: start, head: time, duration: timelineDuration)) {
            selection = .range(range)
        }
    }

    private func cutSelectedRange() {
        guard playback.isReady, let project, case .range(let range) = selection else { return }
        guard let edits = EditorTimeRange.removing(.init(
            range: range, edits: project.edits, takeDuration: timelineDuration
        )) else {
            editErrorMessage = "Select a range containing kept footage and leave at least 0.1 seconds in the recording."
            return
        }
        playback.pauseForEditing()
        if vm.applyTimelineEdits(.init(edits: edits, actionName: "Cut Range")) {
            pendingRangeCutSeek = range.start
            selection = nil
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    private func restoreSelectedRange() {
        guard playback.isReady, let project, case .range(let range) = selection,
            let edits = EditorTimeRange.restoring(.init(
                range: range, edits: project.edits, takeDuration: timelineDuration
            ))
        else { return }
        playback.pauseForEditing()
        if vm.applyTimelineEdits(.init(edits: edits, actionName: "Restore Range")) {
            pendingRangeCutSeek = range.start
            selection = nil
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    private func splitAtPlayhead() {
        guard playback.isReady else { return }
        playback.pauseForEditing()
        layoutDraft = nil
        playback.setPreviewSceneOverride(nil, at: playback.currentTime)
        let insertIndex = sceneEvents.filter { $0.time < playback.currentTime }.count
        if vm.splitProjectScene(at: playback.currentTime, duration: timelineDuration) {
            selection = .segment(max(0, insertIndex))
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    private func deleteSelectedSegment() {
        guard playback.isReady, case .segment(let index) = selection,
            let range = EditorTimeRange.segment(.init(
                eventTimes: sceneEvents.map(\.time), index: index, duration: timelineDuration
            ))
        else { return }
        playback.pauseForEditing()
        if vm.deleteProjectSegment(.init(index: index, duration: timelineDuration)) {
            pendingRangeCutSeek = range.start
            selection = nil
        } else {
            editErrorMessage = vm.detailMessage
        }
    }

    private func joinSelectedSegment() {
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
            switch inspectorTab {
            case .silence:
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button {
                            inspectorTab = .audio
                        } label: {
                            Label("Audio", systemImage: "chevron.left")
                        }
                        .blitzButton(.secondary)
                        Text("Silence removal").font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                    SilenceInspectorPane(session: silence)
                }

            case .text:
                EditorTextInspector(configuration: .init(
                    vm: vm, playback: playback, preview: scenePresetPreview,
                    scene: displayedCanvasScene ?? RecordingScene(settings: vm.settings),
                    layout: captureLayout ?? vm.settings.layout
                ))
            case .zoom:
                TimelineEditingPanel(configuration: .init(
                    vm: vm, playback: playback,
                    preview: scenePresetPreview
                ))
            case .blitzReels:
                if let project {
                    VStack(spacing: 0) {
                        BlitzUI.sectionLabel("BlitzReels", icon: "arrow.up.right")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        BlitzReelsHandoffPanel(project: project, settings: vm.settings)
                    }
                }
            default:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch inspectorTab {
                        case .layout:
                            layoutInspectorContent
                        case .audio:
                            silenceRemovalEntry
                            audioControlsSection
                        default: EmptyView()
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
                .id(inspectorTab)
            }
        }
    }

    private var layoutInspectorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            sceneControlsSection
            divider
            VStack(alignment: .leading, spacing: 12) {
                BlitzInspectorHeading(configuration: .init(title: "Canvas", detail: nil))
                canvasControlsSection
                VStack(spacing: 2) {
                    canvasPaddingSection
                    screenAppearanceSection
                }
            }
            divider
            sourceFramingSection
        }
    }

    private var sourceFramingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showsSourceFraming.toggle()
            } label: {
                HStack {
                    Text("Source framing")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    BlitzSymbol(
                        configuration: .init(
                            name: showsSourceFraming ? "chevron.up" : "chevron.down", size: 12
                        )
                    )
                    .foregroundStyle(BlitzUI.secondaryText)
                }
                .foregroundStyle(BlitzUI.primaryText)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityValue(showsSourceFraming ? "Expanded" : "Collapsed")

            if showsSourceFraming {
                BlitzSegmentedPicker(
                    configuration: .init(
                        title: "Source to frame",
                        options: [SceneLayerKind.screen, .camera],
                        selection: $framingSource,
                        label: { $0 == .screen ? "Screen" : "Camera" }
                    ))
                if framingSource == .screen {
                    screenZoomSection
                    screenFrameSection
                    frameAspectSection(.screen)
                } else if currentEventScene?.enabledSources.contains(.camera) == true {
                    cameraControlsSection
                } else {
                    Text("Choose a composition with Camera to adjust its framing.")
                        .font(.system(size: 11))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
        }
    }

    private var inspectorTabBar: some View {
        HStack(spacing: 2) {
            ForEach([EditorInspectorTab.layout, .audio, .text, .zoom], id: \.self) { tab in
                BlitzTab(
                    configuration: .init(
                        title: tab.rawValue,
                        symbolName: tab.systemImage,
                        isSelected: inspectorTab == tab || (tab == .audio && inspectorTab == .silence),
                        expands: true,
                        action: { inspectorTab = tab }
                    )
                )
                .help(
                    tab == .layout
                        ? "Scene layout and canvas" : tab == .audio ? "Audio and silence removal" : tab.rawValue)
            }
        }
        .frame(maxWidth: .infinity)
        .controlSize(.large)
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector tabs")
    }

    private var silenceRemovalEntry: some View {
        Button(action: openSilenceInspector) {
            HStack(spacing: 10) {
                BlitzSymbol(configuration: .init(name: "waveform.path", size: 20))
                    .foregroundStyle(BlitzUI.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remove silence").font(.system(size: 12, weight: .semibold))
                    Text(silence.loading ? "Finding quiet moments…" : "\(silence.metrics.pauseCount) pauses · \(SilenceTime.label(silence.metrics.removedDuration)) shorter")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                }
                Spacer(minLength: 0)
                BlitzSymbol(configuration: .init(name: "chevron.right", size: 12))
            }
            .padding(12)
            .blitzCard()
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
        .help("Review silence cuts in the Audio pane")
    }

    private func openSilenceInspector() {
        inspectorTab = .silence
    }

    @ViewBuilder
    private var sceneControlsSection: some View {
        if let scene = currentEventScene, captureLayout != nil {
            VStack(alignment: .leading, spacing: 12) {
                BlitzInspectorHeading(
                    configuration: .init(
                        title: "Composition",
                        detail: sceneEvents.count > 1 ? "Segment \(currentEventIndex + 1)" : "Full video"
                    ))
                LazyVGrid(columns: scenePresetColumns, spacing: 8) {
                    ForEach(
                        ScenePreset.allCases.filter { $0.supports(captureLayout ?? .horizontal) },
                        id: \.self
                    ) { preset in
                        let layout = editorLayout(for: preset)
                        BlitzScenePresetCard(
                            preset: preset,
                            layout: captureLayout ?? .horizontal,
                            isSelected: EditorScenePresetSelection.isSelected(
                                .init(preset: preset, scene: scene, layout: layout)),
                            isEnabled: preset.supports(captureLayout ?? .horizontal),
                            preview: scenePresetPreview
                        ) {
                            applyScenePreset(preset)
                        }
                        .help(
                            "\(preset.compactTitle). Applies to this segment. Drag sources in the preview to reposition them."
                        )
                    }
                }
            }
        }
    }

    private var scenePresetPreview: BlitzScenePreview {
        BlitzScenePreview(
            screen: asset(for: .screen).flatMap { library.filmstrips[$0.id]?.first },
            camera: asset(for: .camera).flatMap { library.filmstrips[$0.id]?.first },
            background: displayedCanvasScene?.canvasBackgroundStyle ?? .black
        )
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

            SourceFramingPicker(selection: segmentSceneBinding(\.screenContentMode, fallback: .fill))
        }
    }

    @ViewBuilder
    private var screenZoomSection: some View {
        if currentEventScene?.enabledSources.contains(.screen) == true {
            BlitzInspectorSlider(
                configuration: .init(
                    title: "Crop",
                    value: screenZoomBinding,
                    range: 0...0.75,
                    step: 0.001,
                    valueLabel: screenZoomLabel,
                    onEditingChanged: { if !$0 { commitScreenZoom() } },
                    onReset: {
                        previewScreenZoom(0)
                        commitScreenZoom()
                    }
                ))
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
        guard
            vm.applyProjectSceneEdit(
                eventIndex: index,
                { scene in
                    scene.sceneLayout = layout
                    scene.enabledSources.formUnion([.screen, .camera])
                    scene.sourceOpacities[.screen] = 1
                    scene.sourceOpacities[.camera] = 1
                })
        else {
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

    private func beginEditorCameraCrop() {
        let index = currentEventIndex
        guard sceneEvents.indices.contains(index),
              sceneEvents[index].scene.enabledSources.contains(.camera) else {
            return
        }
        playback.pauseForEditing()
        let scene = sceneEvents[index].scene
        cameraZoomDraft = nil
        cameraCropDraft = EditorCameraCropDraft(
            eventIndex: index,
            originalScene: scene,
            scene: scene
        )
        if let camera = asset(for: .camera) {
            selection = .asset(camera.id)
        }
    }

    private func updateEditorCameraCrop(_ change: EditorCameraCropInteractionChange) {
        guard var draft = cameraCropDraft,
              let sourceAspectRatio = playback.sourceAspectRatios[.camera],
              playback.renderSize.width > 0,
              playback.renderSize.height > 0 else {
            return
        }
        let renderGeometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: playback.renderSize),
            scene: draft.scene,
            origin: .upperLeft
        )
        let cropGeometry = CameraCropGeometry(
            renderGeometry: renderGeometry,
            sourceAspectRatio: sourceAspectRatio
        )
        let startCrop = cropGeometry.cropFrame(
            amount: change.startControl.amount,
            position: change.startControl.position
        )
        let crop: CGRect
        switch change.kind {
        case .move:
            crop = cropGeometry.movedCropFrame(startCrop, delta: change.delta)
        case .resize(let anchor):
            crop = cropGeometry.resizedCropFrame(startCrop, delta: change.delta, anchor: anchor)
        }
        guard let control = cropGeometry.control(for: crop) else { return }
        draft.scene.cameraCropAmount = control.amount
        draft.scene.cameraCropPosition = control.position
        cameraCropDraft = draft
    }

    private func applyEditorCameraCrop() {
        guard let draft = cameraCropDraft else { return }
        let amount = draft.scene.cameraCropAmount
        let position = draft.scene.cameraCropPosition
        let succeeded = vm.applyProjectSceneEdit(eventIndex: draft.eventIndex) { scene in
            scene.cameraCropAmount = amount
            scene.cameraCropPosition = position
        }
        cameraCropDraft = nil
        if !succeeded {
            editErrorMessage = vm.detailMessage
        }
    }

    private func resetEditorCameraCrop() {
        if var draft = cameraCropDraft {
            draft.scene.cameraCropAmount = .zero
            draft.scene.cameraCropPosition = .zero
            cameraCropDraft = draft
            return
        }
        previewCameraZoom(0)
        commitCameraZoom()
    }

    private func cancelEditorCameraCrop() {
        cameraCropDraft = nil
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
            BlitzInspectorSlider(
                configuration: .init(
                    title: "Padding",
                    value: Binding(get: { Double(canvasPaddingValue) }, set: { previewCanvasPadding(CGFloat($0)) }),
                    range: 0...0.12,
                    step: 0.005,
                    valueLabel: "\(Int((canvasPaddingValue * 100).rounded()))%",
                    onEditingChanged: { if !$0 { commitCanvasPadding() } },
                    onReset: {
                        previewCanvasPadding(0)
                        commitCanvasPadding()
                    }
                ))
        }
    }

    private var canvasPaddingValue: CGFloat {
        displayedCanvasScene?.canvasPadding ?? 0
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
            BlitzInspectorSlider(
                configuration: .init(
                    title: "Corners",
                    value: Binding(
                        get: { Double(screenCornerRadiusValue) }, set: { previewScreenCornerRadius(CGFloat($0)) }),
                    range: 0...0.12,
                    step: 0.005,
                    valueLabel: "\(Int((screenCornerRadiusValue * 100).rounded()))%",
                    onEditingChanged: { if !$0 { commitScreenCornerRadius() } },
                    onReset: {
                        previewScreenCornerRadius(0)
                        commitScreenCornerRadius()
                    }
                )
            )
            .help("Round the screen recording")
            Toggle("Shadow", isOn: screenShadowBinding)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
                .toggleStyle(.blitzSwitch)
                .tint(BlitzUI.mint)
                .frame(minHeight: 28)
                .help("Add a soft shadow under the screen recording")
        }
    }

    private var screenCornerRadiusValue: CGFloat {
        displayedCanvasScene?.screenCornerRadius ?? 0
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
            BlitzBackgroundPicker(
                configuration: .init(
                    selection: scene.canvasBackgroundStyle,
                    onSelect: setCanvasBackground
                ))
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

    private var canDeleteSelectedSegment: Bool {
        guard let project, case .segment(let index) = selection,
            let range = EditorTimeRange.segment(.init(
                eventTimes: sceneEvents.map(\.time), index: index, duration: timelineDuration
            ))
        else { return false }
        return EditorTimeRange.removing(.init(
            range: range, edits: project.edits, takeDuration: timelineDuration
        )) != nil
    }

    @ViewBuilder
    private var cameraControlsSection: some View {
        if let scene = currentEventScene, scene.enabledSources.contains(.camera) {
            VStack(alignment: .leading, spacing: 14) {
                if cameraCropDraft == nil,
                   SceneLayout.isCameraInsetFrame(scene.sceneLayout.cameraFrame) {
                    CameraInsetFrameControlPanel(configuration: editorCameraInsetConfiguration)
                }

                CameraImageControls(configuration: editorCameraImageConfiguration)
            }
        }
    }

    private var editorCameraInsetConfiguration: CameraInsetFrameControlsConfiguration {
        let layout = captureLayout ?? .horizontal
        let frame = currentEventScene?.sceneLayout.cameraFrame ?? .zero
        return CameraInsetFrameControlsConfiguration(
            alignment: Binding(
                get: { SceneLayout.cameraInsetAlignment(for: frame) },
                set: { applyEditorCameraInsetChange(.alignment($0)) }
            ),
            shape: Binding(
                get: { SceneLayout.cameraInsetShape(for: frame, in: layout) },
                set: { applyEditorCameraInsetChange(.shape($0)) }
            ),
            size: Binding(
                get: { Double(SceneLayout.cameraInsetSize(for: frame, in: layout)) },
                set: { applyEditorCameraInsetChange(.size(CGFloat($0))) }
            ),
            sizeRange: Double(SceneLayout.minimumCameraInsetSize)...Double(
                SceneLayout.maximumCameraInsetSize(for: layout)
            )
        )
    }

    private func applyEditorCameraInsetChange(_ change: EditorCameraInsetControlChange) {
        guard let scene = currentEventScene, let layout = captureLayout else { return }
        let frame = scene.sceneLayout.cameraFrame
        var alignment = SceneLayout.cameraInsetAlignment(for: frame)
        var shape = SceneLayout.cameraInsetShape(for: frame, in: layout)
        var size = SceneLayout.cameraInsetSize(for: frame, in: layout)

        switch change {
        case .alignment(let value):
            alignment = value
        case .shape(let value):
            shape = value
        case .size(let value):
            size = value
        }

        let sourceAspectRatio = playback.sourceAspectRatios[.camera] ?? SceneLayout.cameraAspectRatio
        let nextFrame = SceneLayout.cameraInsetFrame(
            for: layout,
            alignment: alignment,
            shape: shape,
            size: size,
            sourceAspectRatio: sourceAspectRatio
        )
        playback.pauseForEditing()
        guard vm.applyProjectSceneEdit(eventIndex: currentEventIndex, { editedScene in
            editedScene.sceneLayout.cameraFrame = nextFrame
        }) else {
            editErrorMessage = vm.detailMessage
            return
        }
    }

    private var editorCameraImageConfiguration: CameraImageControlsConfiguration {
        let scene = cameraCropDraft?.scene ?? currentEventScene
        let position = scene?.cameraCropPosition ?? .zero
        let amount = scene?.cameraCropAmount ?? .zero
        let isCentered = max(amount.x, amount.y) < 0.001
            && abs(position.x) < 0.001
            && abs(position.y) < 0.001
        let showsShadow = scene.map { SceneLayout.isCameraInsetFrame($0.sceneLayout.cameraFrame) } ?? false
        return CameraImageControlsConfiguration(
            contentMode: segmentSceneBinding(\.cameraContentMode, fallback: .fill),
            cropZoom: cameraZoomBinding,
            shadowEnabled: segmentSceneBinding(\.cameraShadowEnabled, fallback: false),
            isCropModeEnabled: cameraCropDraft != nil,
            showsShadow: showsShadow,
            isResetDisabled: isCentered,
            onCropZoomEditingChanged: { isEditing in
                if !isEditing {
                    commitCameraZoom()
                }
            },
            onBeginCrop: beginEditorCameraCrop,
            onResetCrop: resetEditorCameraCrop
        )
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
                    .toggleStyle(.blitzSwitch)
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

enum EditorCameraCropInteractionKind: Equatable {
    case move
    case resize(ResizeAnchor)
}

struct EditorCameraCropInteractionChange {
    let kind: EditorCameraCropInteractionKind
    let delta: CGPoint
    let startControl: CameraCropControl
}

private struct EditorCameraCropOverlayConfiguration {
    let scene: RecordingScene
    let renderSize: CGSize
    let sourceAspectRatio: CGFloat
    let onChange: (EditorCameraCropInteractionChange) -> Void
    let onDone: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
}

private struct EditorCameraCropOverlay: View {
    let configuration: EditorCameraCropOverlayConfiguration

    var body: some View {
        GeometryReader { proxy in
            if let presentation = EditorCameraCropPresentation.make(.init(
                containerSize: proxy.size,
                renderSize: configuration.renderSize,
                scene: configuration.scene,
                sourceAspectRatio: configuration.sourceAspectRatio
            )) {
                EditorCameraCropSelectionOverlay(presentation: presentation)

                EditorCameraCropInteractionView(configuration: .init(
                    presentation: presentation,
                    control: CameraCropControl(
                        amount: configuration.scene.cameraCropAmount,
                        position: configuration.scene.cameraCropPosition
                    ),
                    onChange: configuration.onChange
                ))
            }
        }
        .overlay(alignment: .bottom) {
            CropFloatingToolbar(configuration: .init(
                onDone: configuration.onDone,
                onReset: configuration.onReset,
                onCancel: configuration.onCancel
            ))
            .fixedSize()
            .padding(.bottom, 12)
        }
    }
}

private struct EditorCameraCropSelectionOverlay: View {
    let presentation: EditorCameraCropPresentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(presentation.sourceFrame)
                path.addRect(presentation.cropFrame)
            }
            .fill(.black.opacity(0.48), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(.white.opacity(0.34), lineWidth: 1)
                .frame(width: presentation.sourceFrame.width, height: presentation.sourceFrame.height)
                .offset(x: presentation.sourceFrame.minX, y: presentation.sourceFrame.minY)

            Rectangle()
                .stroke(BlitzUI.mint, lineWidth: 2)
                .frame(width: presentation.cropFrame.width, height: presentation.cropFrame.height)
                .overlay { cropHandles }
                .offset(x: presentation.cropFrame.minX, y: presentation.cropFrame.minY)
        }
        .allowsHitTesting(false)
    }

    private var cropHandles: some View {
        ZStack {
            cropHandle(alignment: .topLeading)
            cropHandle(alignment: .topTrailing)
            cropHandle(alignment: .bottomLeading)
            cropHandle(alignment: .bottomTrailing)
        }
    }

    private func cropHandle(alignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(BlitzUI.mint)
            .frame(width: 12, height: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.black.opacity(0.9), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(
                x: alignment.horizontal == .leading ? -6 : 6,
                y: alignment.vertical == .top ? -6 : 6
            )
    }
}

private struct EditorCameraCropInteractionConfiguration {
    let presentation: EditorCameraCropPresentation
    let control: CameraCropControl
    let onChange: (EditorCameraCropInteractionChange) -> Void
}

private struct EditorCameraCropInteractionView: NSViewRepresentable {
    let configuration: EditorCameraCropInteractionConfiguration

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.presentation = configuration.presentation
        view.control = configuration.control
        view.onChange = configuration.onChange
    }

    final class InteractionView: NSView {
        private struct ResizeAnchorRequest {
            let point: CGPoint
            let frame: CGRect
        }

        var presentation: EditorCameraCropPresentation?
        var control = CameraCropControl(amount: .zero, position: .zero)
        var onChange: ((EditorCameraCropInteractionChange) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragKind: EditorCameraCropInteractionKind?
        private var dragStart = CGPoint.zero
        private var dragStartControl = CameraCropControl(amount: .zero, position: .zero)

        override var isFlipped: Bool { true }

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

        override func mouseDown(with event: NSEvent) {
            guard let presentation else { return }
            let point = convert(event.locationInWindow, from: nil)
            let kind: EditorCameraCropInteractionKind?
            if let anchor = resizeAnchor(.init(point: point, frame: presentation.cropFrame)) {
                kind = .resize(anchor)
                anchor.cursor.set()
            } else if presentation.cropFrame.contains(point) {
                kind = .move
                NSCursor.closedHand.set()
            } else {
                kind = nil
            }
            dragKind = kind
            dragStart = point
            dragStartControl = control
        }

        override func mouseDragged(with event: NSEvent) {
            sendChange(event)
        }

        override func mouseUp(with event: NSEvent) {
            sendChange(event)
            dragKind = nil
            updateCursor(event)
        }

        override func mouseMoved(with event: NSEvent) {
            guard dragKind == nil else { return }
            updateCursor(event)
        }

        override func mouseExited(with event: NSEvent) {
            guard dragKind == nil else { return }
            NSCursor.arrow.set()
        }

        private func sendChange(_ event: NSEvent) {
            guard let dragKind, let presentation else { return }
            let point = convert(event.locationInWindow, from: nil)
            let scale = max(0.0001, presentation.pointsPerRenderUnit)
            onChange?(EditorCameraCropInteractionChange(
                kind: dragKind,
                delta: CGPoint(
                    x: (point.x - dragStart.x) / scale,
                    y: (point.y - dragStart.y) / scale
                ),
                startControl: dragStartControl
            ))
        }

        private func updateCursor(_ event: NSEvent) {
            guard let presentation else {
                NSCursor.arrow.set()
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            if let anchor = resizeAnchor(.init(point: point, frame: presentation.cropFrame)) {
                anchor.cursor.set()
            } else if presentation.cropFrame.contains(point) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }

        private func resizeAnchor(_ request: ResizeAnchorRequest) -> ResizeAnchor? {
            let size: CGFloat = 18
            let half = size / 2
            let frame = request.frame
            let targets: [(ResizeAnchor, CGRect)] = [
                (.topLeft, CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size)),
                (.topRight, CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)),
                (.bottomLeft, CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size)),
                (.bottomRight, CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size))
            ]
            return targets.first(where: { $0.1.contains(request.point) })?.0
        }
    }
}

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
                guard let self, let window = self.window, event.window === window,
                    window.isKeyWindow, window.attachedSheet == nil, NSApp.modalWindow == nil,
                    EditorKeyboardCommand.acceptsShortcuts(firstResponder: window.firstResponder)
                else {
                    return event
                }
                return self.onKeyDown?(event) == true ? nil : event
            }
        }
    }
}
