import AppKit
import AVFoundation
import CoreImage
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers


struct EditorView: View {
    @Bindable var vm: RecorderViewModel
    @State var library = EditorMediaLibrary()
    @State var playback = EditorPlaybackController()
    @State var assets: [EditorAsset] = []
    @State var selection: EditorSelection?
    @State var transcript: RecordingTranscript?
    @State var timelineZoom: Double = 1
    @State var showsTimelineShortcuts = false
    @State var pendingRangeCutSeek: Double?
    @State var selectedFormat: OutputVideoFormat = .mov
    @State var selectedResolution: OutputResolution = .p1080
    @State var selectedExportFramesPerSecond = 60
    @State var selectedExportQuality: ExportVideoQuality = .high
    @State var selectedExportPreset: ExportPerformancePreset = .balanced
    @State var selectedExportPlaybackRate = ExportPlaybackRate.normal
    @State var backgroundMusic: ExportBackgroundMusic?
    @State var backgroundMusicBookmarkData: Data?
    @State var exportLayouts: Set<CaptureLayout> = []
    @State var loadedProjectID: UUID?
    @State var isExportPopoverPresented = false
    @State var reloadTask: Task<Void, Never>?
    @State var sceneEvents: [RecordingSceneEvent] = []
    @State var layoutDraft: EditorLayoutDraft?
    @State var screenZoomDraft: Double?
    @State var cameraZoomDraft: Double?
    @State var cameraCropDraft: EditorCameraCropDraft?
    @State var canvasSceneDraft: RecordingScene?
    @State var canvasCommitTask: Task<Void, Never>?
    @State var preservesCanvasPreviewOnNextProjectRefresh = false
    @State var editErrorMessage: String?
    @State var silence = SilenceEditingSession()
    @State var privacy = PrivacyEditingSession()
    @State var inspectorTab: EditorInspectorTab = .silence
    @State var showsSourceFraming = false
    @State var framingSource: SceneLayerKind = .screen
    @State var aspectRatioLockedKinds: Set<SceneLayerKind> = [.screen, .camera]

    var body: some View {
        let tracks = assetTracks
        return VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

            if let exportStatus {
                EditorExportStatusView(configuration: .init(
                    status: exportStatus,
                    open: { NSWorkspace.shared.open($0) },
                    reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                    sendToBlitzReels: { url in
                        guard let project else { return }
                        BlitzReelsHandoffController.shared.selectExport(.init(
                            fileURL: url, project: project, settings: vm.settings
                        ))
                        inspectorTab = .blitzReels
                    },
                    retry: exportVideo,
                    dismiss: {
                        vm.lastExportSucceededURL = nil
                        vm.lastExportError = nil
                        vm.variantExportURLs = []
                    }
                ))
            }

            if !vm.isExportingVariants, vm.variantExportURLs.count > 1 {
                Button("Show all \(vm.variantExportURLs.count) exported videos") {
                    NSWorkspace.shared.activateFileViewerSelecting(vm.variantExportURLs)
                }
                .blitzButton(.quiet)
                .padding(.bottom, 8)
            }

            divider

            EditorWorkspaceSplitView {
                playerColumn
                    .background(BlitzUI.canvasBackground)
            } inspector: {
                EditorInspector(
                    vm: vm,
                    playback: playback,
                    inspectorTab: $inspectorTab,
                    backgroundMusic: $backgroundMusic,
                    backgroundMusicBookmarkData: $backgroundMusicBookmarkData,
                    persistEditorState: persistEditorState,
                    privacy: privacy,
                    silence: silence,
                    project: project,
                    sceneEvents: sceneEvents,
                    captureLayout: captureLayout,
                    canvasAspectRatio: canvasAspectRatio,
                    recordedVideoSources: recordedVideoSources,
                    scenePresetPreview: scenePresetPreview,
                    cameraAssetID: asset(for: .camera)?.id,
                    showsSourceFraming: $showsSourceFraming,
                    framingSource: $framingSource,
                    screenZoomDraft: $screenZoomDraft,
                    cameraZoomDraft: $cameraZoomDraft,
                    cameraCropDraft: $cameraCropDraft,
                    canvasSceneDraft: $canvasSceneDraft,
                    canvasCommitTask: $canvasCommitTask,
                    preservesCanvasPreviewOnNextProjectRefresh: $preservesCanvasPreviewOnNextProjectRefresh,
                    selection: $selection,
                    editErrorMessage: $editErrorMessage,
                    aspectRatioLockedKinds: $aspectRatioLockedKinds,
                    textSelection: placedSelection(.text),
                    zoomSelection: placedSelection(.zoom)
                )
                    .background(BlitzUI.panelBackground)
            } timeline: {
            EditorTimelineView(
                project: vm.editorProject,
                transcript: transcript,
                transcriptionStatus: vm.transcriptionController.jobStatuses[project?.projectPath ?? ""] ?? .notGenerated,
                onGenerateTranscript: {
                    guard let project else { return }
                    vm.transcriptionController.retry(.project(URL(fileURLWithPath: project.projectPath)))
                },
                assets: assets,
                library: library,
                draftScene: layoutDraft?.scene ?? canvasSceneDraft,
                draftSceneEventIndex: layoutDraft?.eventIndex ?? (canvasSceneDraft == nil ? nil : currentEventIndex),
                duration: timelineDuration,
                playback: playback,
                selection: $selection,
                                onSeek: { playback.scrub(to: $0) },
                onSeekEnded: { playback.endScrub() },
                onTogglePlayback: { playback.togglePlayback() },
                onPlaybackRateChange: { playback.setPlaybackRate($0) },
                isInteractive: playback.isReady,
                hiddenAssetIDs: tracks.hiddenIDs,
                mutedAssetIDs: tracks.mutedIDs,
                toggleableAssetIDs: tracks.toggleableIDs,
                onToggleTrack: { toggleTrack($0) },
                onSplit: splitTimelineSelection,
                onDeleteSelection: { _ = deleteSelection() },
                deleteAction: EditorDeleteRouting.action(.init(
                    selection: selection,
                    hasPrivacySelection: inspectorTab == .privacy && privacy.selectedID != nil,
                    assetIsToggleable: {
                        guard case .asset(let id) = selection else { return false }
                        return tracks.toggleableIDs.contains(id)
                    }()
                )),
                onDeleteSegment: deleteSelectedSegment,
                canDeleteSegment: canDeleteSelectedSegment,
                onJoinSegment: joinSelectedSegment,
                onCutRange: cutSelectedRange,
                onRestoreRange: restoreSelectedRange,
                onExtendClip: extendClip,
                onMarkIn: markRangeIn,
                onMarkOut: markRangeOut,
                zoomLevel: $timelineZoom,
                showsShortcuts: $showsTimelineShortcuts,
                silence: silence,
                onOpenSilence: openSilenceInspector,
                onChangePlacedItem: changePlacedItem,
                onRemovePlacedItem: removePlacedItem
            )
            }
        }
        .task(id: "\(project?.projectPath ?? ""):\(String(describing: vm.transcriptionController.jobStatuses[project?.projectPath ?? ""]))") {
            transcript = nil
            guard let project else { return }
            let store = TranscriptArtifactStore()
            let url = store.locations(for: project).jsonURL
            let loaded = await Task.detached(priority: .utility) { try? store.load(from: url) }.value
            guard !Task.isCancelled else { return }
            transcript = loaded
            silence.setTranscript(loaded)
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
            privacy.cancelGesture()
            silence.cancel()
            reloadTask?.cancel()
            reloadTask = nil
            canvasCommitTask?.cancel()
            canvasCommitTask = nil
            playback.teardown()
        }
        .onChange(of: inspectorTab) { _, tab in
            if tab != .privacy { privacy.cancelGesture() }
        }
        .onChange(of: selection) { _, selection in
            if case .placed(let id) = selection {
                selectPlacedItem(id)
                return
            }
            if privacy.selectedID != nil { privacy.select(nil) }
            guard inspectorTab == .layout, case .asset = selection,
                  let source = selectedVideoLayerKind else { return }
            framingSource = source
            showsSourceFraming = true
        }
        .onChange(of: privacy.selectedID) { _, id in
            guard inspectorTab == .privacy else { return }
            if let id { selection = .placed(.init(kind: .mask, value: id)) }
            else if case .placed(let selected) = selection, selected.kind == .mask { selection = nil }
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

    func reloadProject() async {
        guard !Task.isCancelled else { return }
        guard let project = vm.editorProject else {
            assets = []
            sceneEvents = []
            return
        }
        if loadedProjectID != project.id {
            loadedProjectID = project.id
            privacy.select(nil)
            exportLayouts = []
            inspectorTab = .silence
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

    func refreshProject(preservesPreviewSceneOverride: Bool) async {
        guard !Task.isCancelled else { return }
        guard let project = vm.editorProject else {
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

    func fillWindow() {
        vm.onFillEditorWindow?()
    }

    var project: RecordingProject? {
        vm.editorProject
    }

    var timelineDuration: Double {
        EditorSessionMetrics.timelineDuration(
            playbackDuration: playback.duration,
            lastEventTime: project?.sceneEvents.last?.time ?? 0
        )
    }

    var captureLayout: CaptureLayout? {
        project.flatMap { CaptureLayout(rawValue: $0.settings.layout) }
    }

    var canvasAspectRatio: CGFloat {
        EditorSessionMetrics.canvasAspectRatio(renderSize: playback.renderSize, layout: captureLayout)
    }

    var ratioLabel: String {
        EditorSessionMetrics.ratioLabel(captureLayout)
    }

    var segmentBoundaries: [Double] {
        EditorClipSpine.seekTimes(.init(
            edits: project?.edits ?? .empty,
            duration: timelineDuration,
            silenceCuts: silence.cuts,
            sceneEventTimes: project?.sceneEvents.map(\.time) ?? []
        ))
    }

    var deleteRoutingRequest: EditorDeleteRouting.Request {
        .init(
            selection: selection,
            hasPrivacySelection: inspectorTab == .privacy && privacy.selectedID != nil,
            assetIsToggleable: {
                guard case .asset(let id) = selection else { return false }
                return assetTracks.toggleableIDs.contains(id)
            }()
        )
    }

    var assetTracks: EditorAssetTracks.Snapshot {
        EditorAssetTracks.snapshot(.init(
            assets: assets.map { EditorAssetTracks.Item(id: $0.id, kind: $0.kind) },
            hiddenKinds: playback.hiddenKinds,
            hideableKinds: playback.hideableKinds,
            mutedSources: playback.mutedSources,
            muteableSources: playback.muteableSources
        ))
    }

    func layerKind(for asset: EditorAsset) -> SceneLayerKind? {
        EditorAssetTracks.layerKind(asset.kind)
    }

    func audioSource(for asset: EditorAsset) -> CaptureSource? {
        EditorAssetTracks.audioSource(asset.kind)
    }

    func toggleTrack(_ asset: EditorAsset) {
        if let kind = layerKind(for: asset) {
            playback.setHidden(!playback.hiddenKinds.contains(kind), kind: kind)
            persistEditorState("Change Export Track")
        } else if let source = audioSource(for: asset) {
            let isMuted = !playback.mutedSources.contains(source)
            playback.setMuted(isMuted, source: source)
            persistEditorState("\(isMuted ? "Mute" : "Unmute") \(asset.title)")
        }
    }

    func asset(for kind: SceneLayerKind) -> EditorAsset? {
        switch kind {
        case .screen: return assets.first { $0.kind == .screen }
        case .camera: return assets.first { $0.kind == .camera }
        }
    }

    var selectedVideoLayerKind: SceneLayerKind? {
        guard case .asset(let id) = selection,
              let asset = assets.first(where: { $0.id == id }) else {
            return nil
        }
        return layerKind(for: asset)
    }

}
