import SwiftUI

struct EditorCanvasStage: View {
    var playback: EditorPlaybackController
    var inspectorTab: EditorInspectorTab
    var privacy: PrivacyEditingSession
    var textCanvas: EditorTextCanvas.Configuration
    var sourceCropDraft: EditorSourceCropDraft?
    var layoutDraft: EditorLayoutDraft?
    var canvasAspectRatio: CGFloat
    var ratioLabel: String
    /// Shown while a screen or camera layer is selected in the Layout tab.
    var frameRatioBar: EditorFrameRatioBar.Configuration?
    var layers: () -> [EditorCanvasLayer]
    @Binding var editErrorMessage: String?
    var onSelectLayer: (EditorCanvasLayer?) -> Void
    var onMove: (SceneLayerKind, CGSize, Bool) -> Void
    var onResize: (SceneLayerKind, ResizeAnchor, CGSize, Bool) -> Void
    var onCropChange: (EditorSourceCropInteractionChange) -> Void
    var onCropDone: () -> Void
    var onCropReset: () -> Void
    var onCropCancel: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous)
                .fill(Color.black)

            if playback.isReady {
                EditorCompositedPlayer(
                    controller: playback,
                    renderSize: playback.renderSize,
                    previewSceneRevision: playback.previewSceneRevision,
                    cropDraft: sourceCropDraft
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: BlitzUI.cardRadius))
                .allowsHitTesting(false)
            }

            overlay
            if playback.isReady, inspectorTab != .privacy, sourceCropDraft == nil {
                EditorTextCanvas(configuration: textCanvas)
            }
        }
        .aspectRatio(canvasAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
        }
        .overlay(alignment: .top) {
            if let frameRatioBar {
                EditorFrameRatioBar(configuration: frameRatioBar)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if inspectorTab == .privacy, privacy.isDrawing {
                Label("Drag over the area to hide", systemImage: "rectangle.dashed")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .blitzGlass(cornerRadius: BlitzUI.cardRadius)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview, \(ratioLabel)")
        .overlay(alignment: .bottom) {
            if let editErrorMessage {
                Label(editErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(BlitzType.captionEmphasis)
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
                selectedID: privacy.selectedID, drawableKinds: privacy.isDrawing ? playback.hideableKinds : [],
                findings: privacy.visibleFindings
            ))
        } else if playback.isReady, let sourceCropDraft,
                  let sourceAspectRatio = playback.sourceAspectRatios[sourceCropDraft.kind] {
            EditorSourceCropOverlay(configuration: .init(
                kind: sourceCropDraft.kind,
                scene: sourceCropDraft.scene,
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
                    .font(BlitzType.glyph(24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlitzUI.warning)
                Text("The preview could not be built.")
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.supportingText)
                Text(error)
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        } else if layoutDraft == nil {
            ProgressView("Preparing preview…")
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.secondaryText)
        }
    }
}
