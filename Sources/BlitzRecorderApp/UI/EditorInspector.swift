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
    var transcript: RecordingTranscript?
    var project: RecordingProject?
    var sceneEvents: [RecordingSceneEvent]
    var captureLayout: CaptureLayout?
    var canvasAspectRatio: CGFloat
    var recordedVideoSources: Set<CaptureSource>
    var scenePresetPreview: BlitzScenePreview
    let layerAssetIDs: [SceneLayerKind: String]
    var selectedSource: SceneLayerKind?
    @Binding var screenZoomDraft: Double?
    @Binding var cameraZoomDraft: Double?
    @Binding var sourceCropDraft: EditorSourceCropDraft?
    @Binding var canvasSceneDraft: RecordingScene?
    @Binding var canvasCommitTask: Task<Void, Never>?
    @Binding var preservesCanvasPreviewOnNextProjectRefresh: Bool
    @Binding var selection: EditorSelection?
    @Binding var editErrorMessage: String?
    var textSelection: Binding<UUID?>
    var zoomSelection: Binding<UUID?>
    var outputs: EditorOutputsPane

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
            switch inspectorTab {
            case .audio:
                EditorInspectorPane(configuration: .init(
                    title: "Audio",
                    detail: "Set volumes, clean up your voice and add music.",
                    showsFooter: false,
                    content: {
                        EditorAudioInspector(configuration: .init(
                            vm: vm, playback: playback, hasMusic: backgroundMusic != nil,
                            music: {
                                EditorBackgroundMusicControl(
                                    backgroundMusic: $backgroundMusic,
                                    backgroundMusicBookmarkData: $backgroundMusicBookmarkData,
                                    persist: persistEditorState
                                )
                            }
                        ))
                    },
                    footer: { EmptyView() }
                ))
            case .privacy:
                EditorPrivacyInspector(configuration: .init(vm: vm, playback: playback, session: privacy))
            case .silence:
                SilenceInspectorPane(session: silence)
            case .exports:
                outputs

            case .captions:
                EditorCaptionsInspector(configuration: .init(vm: vm, playback: playback, transcript: transcript, selectedID: Binding(get: {
                    if case .placed(let id) = selection, id.kind == .caption { return id.value }
                    return nil
                }, set: { value in
                    selection = value.map { .placed(.init(kind: .caption, value: $0)) }
                })))
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
                            layerAssetIDs: layerAssetIDs,
                            selectedSource: selectedSource,
                            screenZoomDraft: $screenZoomDraft,
                            cameraZoomDraft: $cameraZoomDraft,
                            sourceCropDraft: $sourceCropDraft,
                            canvasSceneDraft: $canvasSceneDraft,
                            canvasCommitTask: $canvasCommitTask,
                            preservesCanvasPreviewOnNextProjectRefresh: $preservesCanvasPreviewOnNextProjectRefresh,
                            selection: $selection,
                            editErrorMessage: $editErrorMessage
                        )
                    },
                    footer: { EmptyView() }
                ))
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorInspectorTabBar(selection: $inspectorTab)
        }
    }

    private var displayedEventScene: RecordingScene? {
        let index = EditorTimelineIndex.eventIndex(at: playback.currentTime, in: sceneEvents)
        return sceneEvents.indices.contains(index) ? sceneEvents[index].scene : nil
    }

}
