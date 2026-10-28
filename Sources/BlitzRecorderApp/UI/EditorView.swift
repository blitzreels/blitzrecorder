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
    @State var transcriptProjectPath: String?
    @State var timelineZoom: Double = 1
    @State var showsTimelineShortcuts = false
    @AppStorage("editor.showsSourceTracks") var showsSourceTracks = false
    @State var pendingRangeCutSeek: Double?
    @State var selectedFormat: OutputVideoFormat = .mov
    @State var selectedResolution: OutputResolution = .p1080
    @State var selectedExportFramesPerSecond = 60
    @State var selectedExportQuality: ExportVideoQuality = .high
    @State var selectedExportPreset: ExportPerformancePreset = .balanced
    @State var selectedExportTargetSize: Int64?
    @State var selectedExportPlaybackRate = ExportPlaybackRate.normal
    @State var backgroundMusic: ExportBackgroundMusic?
    @State var backgroundMusicBookmarkData: Data?
    @State var additionalExportLayouts: Set<CaptureLayout> = []
    @State var loadedProjectID: UUID?
    @State var reloadTask: Task<Void, Never>?
    @State var sceneEvents: [RecordingSceneEvent] = []
    @State var layoutDraft: EditorLayoutDraft?
    @State var screenZoomDraft: Double?
    @State var cameraZoomDraft: Double?
    @State var sourceCropDraft: EditorSourceCropDraft?
    @State var canvasSceneDraft: RecordingScene?
    @State var canvasCommitTask: Task<Void, Never>?
    @State var preservesCanvasPreviewOnNextProjectRefresh = false
    @State var editErrorMessage: String?
    @State var silence = SilenceEditingSession()
    @State var privacy = PrivacyEditingSession()
    @State var inspectorTab: EditorInspectorTab = .silence
    @State var exportDestination: EditorExportDestination = .file
    @State var preparesHostedExport = false
    @State var showsExportResult = false
    @State var shareOutcome: EditorOutputResult?
    @State var aspectRatioLockedKinds: Set<SceneLayerKind> = [.screen, .camera, .secondCamera]

    var body: some View {
        let tracks = assetTracks
        return VStack(spacing: 0) {
            toolbar
                .blitzWindowToolbar()

            divider

            EditorWorkspaceSplitView(showsSourceTracks: showsSourceTracks) {
                playerColumn
                    .background(BlitzUI.canvasBackground)
                    .overlay(alignment: .bottom) {
                        editorNotice
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            .animation(.spring(duration: 0.18, bounce: 0), value: noticeKey)
                    }
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
                    transcript: transcript,
                    project: project,
                    sceneEvents: sceneEvents,
                    captureLayout: captureLayout,
                    canvasAspectRatio: canvasAspectRatio,
                    recordedVideoSources: recordedVideoSources,
                    scenePresetPreview: scenePresetPreview,
                    layerAssetIDs: SceneLayerKind.allCases.reduce(into: [:]) { ids, kind in
                        ids[kind] = asset(for: kind)?.id
                    },
                    selectedSource: selectedVideoLayerKind,
                    screenZoomDraft: $screenZoomDraft,
                    cameraZoomDraft: $cameraZoomDraft,
                    sourceCropDraft: $sourceCropDraft,
                    canvasSceneDraft: $canvasSceneDraft,
                    canvasCommitTask: $canvasCommitTask,
                    preservesCanvasPreviewOnNextProjectRefresh: $preservesCanvasPreviewOnNextProjectRefresh,
                    selection: $selection,
                    editErrorMessage: $editErrorMessage,
                    textSelection: placedSelection(.text),
                    zoomSelection: placedSelection(.zoom),
                    outputs: outputsPane
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
                onChangeTrackVolume: vm.changeEditorTrackVolume,
                onChangeAudioRegion: vm.changeEditorAudioRegion,
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
                onRestoreRange: restoreSelectedRange,
                onTrimClip: trimClip,
                onMarkIn: markRangeIn,
                onMarkOut: markRangeOut,
                zoomLevel: $timelineZoom,
                showsShortcuts: $showsTimelineShortcuts,
                showsSourceTracks: $showsSourceTracks,
                silence: silence,
                onOpenSilence: openSilenceInspector,
                onChangePlacedItem: changePlacedItem,
                onRemovePlacedItem: removePlacedItem
            )
            }
        }
        .task(id: "\(project?.projectPath ?? ""):\(String(describing: vm.transcriptionController.jobStatuses[project?.projectPath ?? ""]))") {
            if transcriptProjectPath != project?.projectPath {
                transcript = nil
                transcriptProjectPath = project?.projectPath
                silence.setTranscript(nil)
            }
            guard let project else { silence.setTranscriptLoading(false); return }
            if transcript != nil, vm.transcriptionController.jobStatuses[project.projectPath]?.isRunning == true {
                silence.setTranscriptLoading(false)
                return
            }
            silence.setTranscriptLoading(true)
            let store = TranscriptArtifactStore()
            let url = store.locations(for: project).jsonURL
            let loaded = await Task.detached(priority: .utility) { try? store.load(from: url) }.value
            guard !Task.isCancelled else { return }
            silence.setTranscriptLoading(false)
            transcript = loaded
            silence.setTranscript(loaded)
        }
        .task(id: "\(playback.heardMicrophoneURL?.path ?? "-")|\(assets.first { $0.kind == .microphone }.flatMap { library.durations[$0.id] } != nil)") {
            guard let microphone = assets.first(where: { $0.kind == .microphone }),
                  library.durations[microphone.id] != nil else { return }
            await library.showWaveform(.init(assetID: microphone.id, url: playback.heardMicrophoneURL ?? microphone.url))
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
                sourceCropDraft = nil
                canvasSceneDraft = nil
            }
            reloadTask = task
        }
        .onChange(of: HostedVideoShareController.shared.isRunning) { wasRunning, isRunning in
            let sharing = HostedVideoShareController.shared
            guard wasRunning, !isRunning, let path = project?.projectPath, sharing.projectPath == path else { return }
            if let link = sharing.shareURL {
                BlitzClipboard.copyInBackground(link.absoluteString)
                shareOutcome = .shared(link: link, file: sharing.fileURL)
            } else if let message = sharing.transferMessage {
                shareOutcome = .shareFailed(message)
            }
        }
        .onChange(of: project?.projectPath) {
            showsExportResult = false
            shareOutcome = nil
        }
        .onChange(of: vm.exports.isEditorExportPresented, initial: true) { _, requested in
            guard requested else { return }
            vm.exports.isEditorExportPresented = false
            showOutputs(.file)
        }
        .onChange(of: vm.isEditorVisible) { _, visible in
            guard !visible else { return }
            playback.pauseForEditing()
            NowPlayingController.shared.deactivate(playback)
            showsTimelineShortcuts = false
            privacy.cancelGesture()
        }
        .onChange(of: project?.projectPath, initial: true) {
            let sharing = HostedVideoShareController.shared
            preparesHostedExport = !sharing.isRunning && !sharing.belongsToProject(project?.projectPath)
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


    enum EditorNoticeKey: Hashable {
        case none, uploading
        case result(EditorOutputResult)
    }

    var noticeKey: EditorNoticeKey {
        let sharing = HostedVideoShareController.shared
        if sharing.isRunning, sharing.transferProgress != nil { return inspectorTab == .exports && exportDestination == .link ? .none : .uploading }
        return outputResult.map(EditorNoticeKey.result) ?? .none
    }

    /// The newest export or link made in this editor. A share upload replaces its own export's result.
    private var outputResult: EditorOutputResult? {
        if let shareOutcome { return shareOutcome }
        guard showsExportResult, !vm.isExporting else { return nil }
        if let error = vm.exports.lastExportError { return .exportFailed(error) }
        guard let url = vm.exports.lastExportSucceededURL else { return nil }
        let sharing = HostedVideoShareController.shared
        if sharing.isRunning, sharing.fileURL == url { return nil }
        return .exported(files: vm.exports.variantExportURLs.count > 1 ? vm.exports.variantExportURLs : [url])
    }

    private func dismissOutputResult() {
        shareOutcome = nil
        showsExportResult = false
        vm.exports.lastExportSucceededURL = nil
        vm.exports.lastExportError = nil
        vm.exports.variantExportURLs = []
    }

    @ViewBuilder var editorNotice: some View {
        switch noticeKey {
        case .none:
            EmptyView()
        case .uploading:
            if let progress = HostedVideoShareController.shared.transferProgress {
                HStack(spacing: 16) {
                    HostedVideoProgressView(presentation: .transfer(progress))
                        .frame(maxWidth: .infinity)
                    Button {
                        preparesHostedExport = false
                        showOutputs(.link)
                    } label: { Label("View", systemImage: BlitzSymbols.share) }
                    .blitzButton(.secondary)
                }
                .editorNoticeSurface()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .result(let result):
            EditorOutputResultCard(configuration: .init(
                result: result,
                canShare: HostedVideoShareController.shared.canShare && !HostedVideoShareController.shared.isRunning,
                share: { url in
                    dismissOutputResult()
                    shareExportedFile(url)
                },
                sendToBlitzReels: { url in handleExportFollowUp(.sendToBlitzReels(url)) },
                showSharing: {
                    preparesHostedExport = false
                    showOutputs(.link)
                },
                dismiss: dismissOutputResult
            ))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    func shareExportedFile(_ url: URL) {
        handleExportFollowUp(.share(url))
        HostedVideoShareController.shared.start()
    }

    private func handleExportFollowUp(_ followUp: EditorExportFollowUp) {
        switch followUp {
        case .share(let url):
            preparesHostedExport = false
            HostedVideoShareController.shared.select(.init(fileURL: url, projectPath: project?.projectPath))
            showOutputs(.link)
        case .sendToBlitzReels(let url):
            guard let project else { return }
            BlitzReelsHandoffController.shared.selectExport(.init(fileURL: url, project: project, settings: vm.settings))
            inspectorTab = .blitzReels
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
            additionalExportLayouts = []
            inspectorTab = .silence
        }
        EditorCursorTrackCache.shared.prepare(directory: project.takeDirectoryPath)
        privacy.configure(.init(vm: vm, playback: playback))
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
            await playback.reloadAudioIfNeeded(.init(project: project, baseSettings: vm.settings))
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

    /// The canvas layer that shows this file in the current scene: `camera-2` is the second camera in a
    /// two-camera scene, and Camera 1's layer in a "Camera 2" scene.
    func layerKind(for asset: EditorAsset) -> SceneLayerKind? {
        guard asset.kind == .camera, let scene = currentEventScene else { return EditorAssetTracks.layerKind(asset.kind) }
        let roles = Set(assets.map(\.role))
        if scene.sceneLayout.secondCameraFrame != nil, scene.feed(for: .secondCamera, available: roles) == asset.role,
           scene.feed(for: .camera, available: roles) != asset.role {
            return .secondCamera
        }
        return .camera
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
        let roles = Set(assets.map(\.role))
        let feed = currentEventScene?.feed(for: kind, available: roles) ?? kind.defaultFeed
        return assets.first { $0.role == feed } ?? assets.first { $0.role == kind.defaultFeed }
    }

    var selectedVideoLayerKind: SceneLayerKind? {
        guard case .asset(let id) = selection,
              let asset = assets.first(where: { $0.id == id }) else {
            return nil
        }
        return layerKind(for: asset)
    }

}
