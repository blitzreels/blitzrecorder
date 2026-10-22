import SwiftUI

extension EditorLayoutInspector {
    @ViewBuilder
    var backgroundSection: some View {
        if let scene = displayedCanvasScene {
            let isVisible = EditorCanvasAppearance.showsBackground(scene)
            VStack(alignment: .leading, spacing: 12) {
                BlitzInspectorHeading(configuration: .init(title: "Background", detail: nil))
                BlitzInspectorSlider(
                    configuration: .init(
                        title: "Spacing",
                        value: Binding(get: { Double(canvasPaddingValue) }, set: { previewCanvasPadding(CGFloat($0)) }),
                        range: 0...0.12,
                        step: 0.005,
                        valueLabel: canvasPaddingValue < 0.001 ? "None" : "\(Int((canvasPaddingValue * 100).rounded()))%",
                        onEditingChanged: { if !$0 { commitCanvasSceneDraft() } },
                        onReset: {
                            previewCanvasPadding(0)
                            commitCanvasSceneDraft()
                        }
                    ))
                    .help("Space around your recording, filled with the background")
                if isVisible {
                    EditorBackgroundSwatches(configuration: .init(
                        selection: scene.canvasBackgroundStyle,
                        onSelect: setCanvasBackground
                    ))
                    if scene.renderedSources.contains(.screen) {
                        BlitzInspectorSlider(
                            configuration: .init(
                                title: "Corners",
                                value: Binding(
                                    get: { Double(screenCornerRadiusValue) },
                                    set: { previewScreenCornerRadius(CGFloat($0)) }),
                                range: 0...0.12,
                                step: 0.005,
                                valueLabel: "\(Int((screenCornerRadiusValue * 100).rounded()))%",
                                onEditingChanged: { if !$0 { commitCanvasSceneDraft() } },
                                onReset: {
                                    previewScreenCornerRadius(0)
                                    commitCanvasSceneDraft()
                                }
                            ))
                            .help("Round the screen recording")
                        Toggle("Shadow", isOn: screenShadowBinding)
                            .font(BlitzType.captionEmphasis)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .toggleStyle(.blitzSwitch)
                            .tint(BlitzUI.accent)
                            .frame(minHeight: 28)
                            .help("Add a soft shadow under the screen recording")
                    }
                } else {
                    Text("Your recording fills the frame. Add spacing to show a background.")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func setCanvasBackground(_ style: CanvasBackgroundStyle) {
        previewCanvasScene { scene in
            scene.canvasBackgroundStyle = style
        }
        scheduleCanvasSceneCommit()
        selection = .segment(currentEventIndex)
    }

    private var canvasPaddingValue: CGFloat {
        displayedCanvasScene?.canvasPadding ?? 0
    }

    private func previewCanvasPadding(_ padding: CGFloat) {
        let clamped = EditorCanvasAppearance.clampedPadding(padding)
        previewCanvasScene { scene in
            scene.canvasPadding = clamped
        }
    }

    private var screenCornerRadiusValue: CGFloat {
        displayedCanvasScene?.screenCornerRadius ?? 0
    }

    private func previewScreenCornerRadius(_ radius: CGFloat) {
        let clamped = EditorCanvasAppearance.clampedCornerRadius(radius)
        previewCanvasScene { scene in
            scene.screenCornerRadius = clamped
        }
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
        let succeeded = vm.applyProjectSceneEdit(eventIndex: index) {
            EditorCanvasAppearance.copy(draft, into: &$0)
        }
        if !succeeded {
            preservesCanvasPreviewOnNextProjectRefresh = false
            canvasSceneDraft = nil
            playback.setPreviewSceneOverride(nil, at: playback.currentTime)
            editErrorMessage = vm.detailMessage
        }
    }
}
