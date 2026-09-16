import SwiftUI

struct EditorCanvasStage: View {
    var playback: EditorPlaybackController
    var inspectorTab: EditorInspectorTab
    var privacy: PrivacyEditingSession
    var cameraCropDraft: EditorCameraCropDraft?
    var layoutDraft: EditorLayoutDraft?
    var canvasAspectRatio: CGFloat
    var ratioLabel: String
    var layers: () -> [EditorCanvasLayer]
    @Binding var editErrorMessage: String?
    var onSelectLayer: (EditorCanvasLayer) -> Void
    var onMove: (SceneLayerKind, CGSize, Bool) -> Void
    var onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void
    var onCropChange: (EditorCameraCropInteractionChange) -> Void
    var onCropDone: () -> Void
    var onCropReset: () -> Void
    var onCropCancel: () -> Void

    var body: some View {
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

            overlay
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

    @ViewBuilder
    private var overlay: some View {
        if playback.isReady, inspectorTab == .privacy,
           let scene = playback.scene(at: playback.currentTime) {
            EditorPrivacyCanvas(configuration: .init(
                session: privacy, scene: scene, renderSize: playback.renderSize,
                aspectRatios: playback.sourceAspectRatios, hiddenKinds: playback.hiddenKinds,
                masks: privacy.displayedMasks.filter { $0.isVisible(at: playback.currentTime) },
                selectedID: privacy.selectedID, drawingSource: privacy.isDrawing ? privacy.selected?.source : nil
            ))
        } else if playback.isReady, let cameraCropDraft,
                  let sourceAspectRatio = playback.sourceAspectRatios[.camera] {
            EditorCameraCropOverlay(configuration: .init(
                scene: cameraCropDraft.scene,
                renderSize: playback.renderSize,
                sourceAspectRatio: sourceAspectRatio,
                onChange: onCropChange,
                onDone: onCropDone,
                onReset: onCropReset,
                onCancel: onCropCancel
            ))
        } else if playback.isReady {
            EditorCanvasLayerOverlay(
                layers: layers(),
                onSelect: onSelectLayer,
                onMove: onMove,
                onResize: onResize
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
            ProgressView("Preparing preview…")
                .font(.system(size: 12))
                .foregroundStyle(BlitzUI.secondaryText)
        }
    }
}
