import SwiftUI

struct EditorTextInspector: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let preview: BlitzScenePreview
        let scene: RecordingScene
        let layout: CaptureLayout
        let selectedID: Binding<UUID?>
    }

    let configuration: Configuration
    @State private var draft = EditorTextDraft()
    @State private var error: String?
    @FocusState private var isTextFocused: Bool

    private var edits: TimelineEdits { configuration.vm.editorProject?.edits ?? .empty }
    private var duration: Double { configuration.playback.duration }
    private var sortedOverlays: [TextOverlay] { edits.textOverlays.sorted { $0.start < $1.start } }

    var body: some View {
        ScrollViewReader { proxy in
            EditorInspectorPane(configuration: .init(
                title: "Text",
                detail: "Add titles and callouts on top of your video.",
                showsFooter: true,
                content: {
                    VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                        composer.id("composer")
                        timing
                        Toggle("Fade in and out", isOn: $draft.fades)
                            .toggleStyle(.blitzSwitch)
                            .help("Turn off for text that appears and disappears instantly. Applies to this overlay.")
                        if !sortedOverlays.isEmpty {
                            Rectangle().fill(BlitzUI.separator).frame(height: 1)
                            overlayList
                        }
                    }
                },
                footer: { footer }
            ))
            .onChange(of: draft.original?.id) { _, _ in proxy.scrollTo("composer", anchor: .top) }
        }
        .onAppear(perform: loadSelection)
        .onChange(of: (configuration.vm.lastExportedProject?.projectPath ?? "") + (configuration.vm.lastExportedProject?.selectedOutputLayout.rawValue ?? "")) { loadSelection() }
        .onChange(of: configuration.selectedID.wrappedValue) { _, _ in loadSelection() }
        .onChange(of: edits.textOverlays) { _, overlays in
            if let id = draft.original?.id, !overlays.contains(where: { $0.id == id }) { resetDraft() }
            else if let id = configuration.selectedID.wrappedValue,
                    let overlay = overlays.first(where: { $0.id == id }) { draft.edit(overlay) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            BlitzInspectorHeading(configuration: .init(
                title: draft.isEditing ? "Edit text" : "Add text", detail: "On your video"
            ))
            TextField("What would you like to say?", text: $draft.text, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.plain)
                .font(BlitzType.section)
                .padding(12)
                .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: BlitzControlMetrics.radius)
                        .strokeBorder(isTextFocused ? BlitzUI.mint.opacity(0.7) : BlitzUI.panelStroke, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .focused($isTextFocused)
                .accessibilityLabel("Overlay text")
                .onChange(of: draft.text) { _, value in
                    if value.count > 500 { draft.text = String(value.prefix(500)) }
                }
            HStack(alignment: .top, spacing: 4) {
                ForEach(TextOverlayPreset.allCases, id: \.self) { preset in
                    BlitzVisualChoice(configuration: .init(
                        title: preset.displayName,
                        help: "\(preset.displayName). Preview its appearance and position on your video.",
                        isSelected: draft.preset == preset,
                        action: { draft.preset = preset },
                        preview: {
                            EditorTextStylePreview(configuration: .init(
                                preset: preset, text: draft.text,
                                source: configuration.preview, scene: configuration.scene, layout: configuration.layout
                            ))
                        }
                    ))
                }
            }
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BlitzInspectorHeading(configuration: .init(title: "Timing", detail: nil))
                Button {
                    draft.moveToPlayhead(.init(time: configuration.playback.currentTime, duration: duration))
                } label: {
                    Label("Use playhead", systemImage: "playhead")
                }
                .blitzButton(.quiet).controlSize(.small)
                .help("Start this text at the playhead, keeping its duration when space allows.")
                .fixedSize()
            }
            HStack(spacing: 10) {
                timeField(.init(title: "Start", value: $draft.startText))
                timeField(.init(title: "End", value: $draft.endText))
            }
            if let range = draft.range(duration) {
                let projection = EditorTimelineProjection(.init(duration: duration, cuts: edits.cuts))
                HStack {
                    Text("Visible for \(SilenceTime.label(projection.displayTime(range.end) - projection.displayTime(range.start)))")
                    Spacer(minLength: 0)
                    Text("min:sec")
                }
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                Text("Start and end refer to the original recording.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            } else {
                Text("Enter a start before the end, within \(EditorPlaybackPosition.display(duration)).")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.recordRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var overlayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlitzInspectorHeading(configuration: .init(title: "In this video", detail: "\(sortedOverlays.count)"))
            ForEach(sortedOverlays) { overlay in
                HStack(spacing: 4) {
                    Button {
                        configuration.selectedID.wrappedValue = overlay.id
                        draft.edit(overlay)
                        error = nil
                        configuration.playback.pauseForEditing()
                        configuration.playback.seek(to: overlay.start + min(0.3, overlay.duration / 2))
                        isTextFocused = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "textformat")
                                .font(BlitzType.glyph(14)).foregroundStyle(BlitzUI.secondaryText)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(overlay.text).font(BlitzType.label).lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(SilenceTime.label(overlay.start))–\(SilenceTime.label(overlay.end)) · \(overlay.style.preset.displayName)")
                                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(BlitzSelectionButtonStyle(isSelected: draft.original?.id == overlay.id))
                    .pointingHandCursor()
                    .accessibilityLabel("Edit \(overlay.text)")
                    .help("Edit this overlay and show it in the preview.")
                    Button {
                        configuration.playback.play(from: overlay.start)
                    } label: {
                        Image(systemName: "play")
                    }
                    .blitzButton(.quiet).controlSize(.small)
                    .accessibilityLabel("Preview \(overlay.text)").help("Play from this overlay")
                    Button(role: .destructive) {
                        var updated = edits
                        updated.textOverlays.removeAll { $0.id == overlay.id }
                        _ = apply(.init(edits: updated, actionName: "Remove Text"))
                    } label: {
                        Image(systemName: "trash")
                    }
                    .blitzButton(.quiet).controlSize(.small)
                    .accessibilityLabel("Remove \(overlay.text)").help("Remove this overlay. Undo with ⌘Z.")
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error {
                Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.recordRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if draft.isEditing {
                    Button(action: resetDraft) { Label("Cancel", systemImage: "xmark") }.blitzButton(.secondary)
                }
                Button(action: saveText) {
                    Label(draft.isEditing ? "Save changes" : "Add to video",
                          systemImage: draft.isEditing ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.accent)
                .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.range(duration) == nil)
            }
            Text("Saved in this project · ⌘Z to undo")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                .frame(maxWidth: .infinity)
        }
    }

    private struct TimeField {
        let title: String
        let value: Binding<String>
    }

    private func timeField(_ field: TimeField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.title).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            TextField("00:00.00", text: field.value)
                .textFieldStyle(.plain)
                .font(BlitzType.label.monospacedDigit())
                .accessibilityLabel("Text \(field.title.lowercased()) time")
                .help("Enter minutes:seconds, or seconds. Decimals are supported.")
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
    }

    private func resetDraft() {
        configuration.selectedID.wrappedValue = nil
        draft = EditorTextDraft()
        draft.moveToPlayhead(.init(time: configuration.playback.currentTime, duration: duration))
        error = nil
    }

    private func loadSelection() {
        guard let id = configuration.selectedID.wrappedValue,
              let overlay = edits.textOverlays.first(where: { $0.id == id }) else { resetDraft(); return }
        draft.edit(overlay)
        error = nil
    }

    private func apply(_ change: EditorTimelineEditsChange) -> Bool {
        configuration.playback.pauseForEditing()
        guard configuration.vm.applyOutputTextEdits(change) else {
            error = configuration.vm.detailMessage
            return false
        }
        error = nil
        return true
    }

    private func saveText() {
        guard let overlay = draft.overlay(duration) else { return }
        var updated = edits
        updated.textOverlays.removeAll { $0.id == overlay.id }
        updated.textOverlays.append(overlay)
        guard apply(.init(edits: updated, actionName: draft.isEditing ? "Edit Text" : "Add Text")) else { return }
        configuration.playback.seek(to: overlay.start + min(0.3, overlay.duration / 2))
        resetDraft()
        isTextFocused = false
    }
}

struct EditorTextStylePreview: View {
    struct Configuration {
        let preset: TextOverlayPreset
        let text: String
        let source: BlitzScenePreview
        let scene: RecordingScene
        let layout: CaptureLayout
    }

    let configuration: Configuration

    var body: some View {
        ZStack {
            BlitzSceneLayoutThumbnail(
                layout: configuration.layout, sceneLayout: configuration.scene.sceneLayout,
                visibleSources: configuration.scene.enabledSources, preview: configuration.source
            )
            if let image = overlayImage {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }

    private var overlayImage: CGImage? {
        let text = configuration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return TimelineOverlayRenderer.image(.init(
            overlay: .init(start: 0, end: 3, text: text.isEmpty ? "Your text" : text,
                           frame: TextOverlay.defaultFrame(for: configuration.preset),
                           style: .preset(configuration.preset)),
            size: CGSize(width: 640, height: 640 / configuration.layout.aspectRatio)
        ))
    }
}
