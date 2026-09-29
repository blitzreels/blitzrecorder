import SwiftUI

struct EditorInspector: View {
    @Bindable var vm: RecorderViewModel
    var playback: EditorPlaybackController
    @Binding var inspectorTab: EditorInspectorTab
    @Binding var backgroundMusic: ExportBackgroundMusic?
    @Binding var backgroundMusicBookmarkData: Data?
    var persistEditorState: (String) -> Void
    var privacy: PrivacyEditingSession
    var silence: SilenceEditingSession
    var project: RecordingProject?
    var sceneEvents: [RecordingSceneEvent]
    var captureLayout: CaptureLayout?
    var canvasAspectRatio: CGFloat
    var recordedVideoSources: Set<CaptureSource>
    var scenePresetPreview: BlitzScenePreview
    var cameraAssetID: String?
    @Binding var showsSourceFraming: Bool
    @Binding var framingSource: SceneLayerKind
    @Binding var screenZoomDraft: Double?
    @Binding var cameraZoomDraft: Double?
    @Binding var cameraCropDraft: EditorCameraCropDraft?
    @Binding var canvasSceneDraft: RecordingScene?
    @Binding var canvasCommitTask: Task<Void, Never>?
    @Binding var preservesCanvasPreviewOnNextProjectRefresh: Bool
    @Binding var selection: EditorSelection?
    @Binding var editErrorMessage: String?
    @Binding var aspectRatioLockedKinds: Set<SceneLayerKind>
    var textSelection: Binding<UUID?>
    var zoomSelection: Binding<UUID?>

    var body: some View {
        VStack(spacing: 0) {
            EditorInspectorTabBar(selection: $inspectorTab)
            divider
            switch inspectorTab {
            case .audio:
                EditorInspectorPane(configuration: .init(
                    title: "Audio",
                    detail: "Clean up your voice and add background music.",
                    showsFooter: false,
                    content: {
                        EditorAudioInspector(configuration: .init(vm: vm, playback: playback))
                        Rectangle().fill(BlitzUI.separator).frame(height: 1)
                        EditorBackgroundMusicControl(
                            backgroundMusic: $backgroundMusic,
                            backgroundMusicBookmarkData: $backgroundMusicBookmarkData,
                            persist: persistEditorState
                        )
                    },
                    footer: { EmptyView() }
                ))
            case .privacy:
                EditorPrivacyInspector(configuration: .init(vm: vm, playback: playback, session: privacy))
            case .silence:
                SilenceInspectorPane(session: silence)

            case .text:
                EditorTextInspector(configuration: .init(
                    vm: vm, playback: playback, preview: scenePresetPreview,
                    scene: canvasSceneDraft ?? displayedEventScene ?? RecordingScene(settings: vm.settings),
                    layout: captureLayout ?? vm.settings.layout,
                    selectedID: textSelection
                ))
            case .zoom:
                TimelineEditingPanel(configuration: .init(
                    vm: vm, playback: playback,
                    preview: scenePresetPreview,
                    selectedKeyframeID: zoomSelection
                ))
            case .blitzReels:
                if let project {
                    BlitzReelsHandoffPanel(project: project, settings: vm.settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(BlitzUI.panelBackground)
                }
            case .layout:
                EditorInspectorPane(configuration: .init(
                    title: "Layout",
                    detail: "Arrange your screen and camera on the canvas.",
                    showsFooter: false,
                    content: {
                        EditorLayoutInspector(
                            vm: vm,
                            playback: playback,
                            sceneEvents: sceneEvents,
                            captureLayout: captureLayout,
                            canvasAspectRatio: canvasAspectRatio,
                            recordedVideoSources: recordedVideoSources,
                            scenePresetPreview: scenePresetPreview,
                            cameraAssetID: cameraAssetID,
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
                            aspectRatioLockedKinds: $aspectRatioLockedKinds
                        )
                    },
                    footer: { EmptyView() }
                ))
            }
        }
    }

    private var displayedEventScene: RecordingScene? {
        let index = EditorTimelineIndex.eventIndex(at: playback.currentTime, in: sceneEvents)
        return sceneEvents.indices.contains(index) ? sceneEvents[index].scene : nil
    }

    private var divider: some View {
        Rectangle()
            .fill(BlitzUI.separator)
            .frame(height: 1)
    }
}
