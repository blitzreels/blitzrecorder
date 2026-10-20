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
    @State private var newText = ""
    @State private var newPreset = TextOverlayPreset.title
    @State private var editText = ""
    @State private var editTextID: UUID?
    @State private var pendingText: Task<Void, Never>?
    @State private var error: String?
    @FocusState private var isTextFocused: Bool

    private var edits: TimelineEdits { configuration.vm.editorProject?.edits ?? .empty }
    private var playback: EditorPlaybackController { configuration.playback }
    private var duration: Double { playback.duration }
    private var sortedOverlays: [TextOverlay] { edits.textOverlays.sorted { $0.start < $1.start } }
    private var selected: TextOverlay? {
        configuration.selectedID.wrappedValue.flatMap { id in edits.textOverlays.first { $0.id == id } }
    }

    var body: some View {
        EditorInspectorPane(configuration: .init(
            title: "Text",
            detail: "Add titles and callouts on top of your video.",
            showsFooter: false,
            content: {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    if let selected {
                        EditorInspectorSection(configuration: .init(title: "Edit text", content: { editor(selected) }))
                        EditorInspectorSection(configuration: .init(title: "When", content: { when(selected) }))
                    } else {
                        EditorInspectorSection(configuration: .init(title: "Add text", content: { composer }))
                    }
                    if !sortedOverlays.isEmpty {
                        EditorInspectorSection(configuration: .init(title: "In this video", content: { overlayList }))
                    }
                    if let error {
                        Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            },
            footer: { EmptyView() }
        ))
        .onAppear(perform: syncEditText)
        .onChange(of: configuration.selectedID.wrappedValue) { _, _ in
            flushText()
            syncEditText()
        }
        .onChange(of: selected?.text) { _, _ in if pendingText == nil { syncEditText() } }
        .onDisappear(perform: flushText)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            textField(.init(text: $newText, placeholder: "What would you like to say?"))
                .onSubmit(addText)
            styleChoices(.init(selection: newPreset, text: newText, choose: { newPreset = $0 }))
            Button(action: addText) {
                Label("Add at playhead", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .blitzButton(.accent)
            .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duration <= 0)
            Text("Shows for 3 seconds. Change it after adding.")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
        }
    }

    private func editor(_ overlay: TextOverlay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            textField(.init(text: $editText, placeholder: "Text"))
                .onChange(of: editText) { _, _ in scheduleTextSave() }
                .onSubmit(flushText)
            styleChoices(.init(selection: overlay.style.preset, text: editText, choose: { preset in
                update(.init(overlay: TextOverlayEditing.restyled(.init(overlay: overlay, preset: preset)),
                             actionName: "Change Text Style"))
            }))
        }
    }

    private func when(_ overlay: TextOverlay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BlitzTimeRangeEditor(configuration: .init(
                range: .init(start: overlay.start, end: overlay.end),
                duration: duration,
                playhead: playback.currentTime,
                minimumLength: min(TextOverlayEditing.minimumLength, overlay.end - overlay.start),
                onChange: { range in
                    var changed = overlay
                    changed.start = range.start
                    changed.end = range.end
                    if update(.init(overlay: changed, actionName: "Change Text Timing")), range.start != overlay.start {
                        playback.seek(to: range.start + min(0.3, range.duration / 2))
                    }
                }
            ))
            Toggle("Fade in and out", isOn: Binding(
                get: { overlay.fadeSeconds > 0 },
                set: { fades in
                    update(.init(overlay: TextOverlayEditing.fading(.init(overlay: overlay, fades: fades)),
                                 actionName: "Change Text Fade"))
                }
            ))
            .toggleStyle(.blitzSwitch)
            HStack(spacing: 8) {
                Button("Done") { configuration.selectedID.wrappedValue = nil }
                    .blitzButton(.secondary).controlSize(.small)
                    .help("Finish editing and add more text")
                Spacer(minLength: 0)
                BlitzInlineActions(entries: actions(overlay))
                    .controlSize(.small)
                    .fixedSize()
            }
        }
    }

    private var overlayList: some View {
        VStack(spacing: 2) {
            ForEach(sortedOverlays) { overlay in
                Button { select(overlay) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat")
                            .font(BlitzType.glyph(13)).foregroundStyle(BlitzUI.secondaryText).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(overlay.text).font(BlitzType.navigation).lineLimit(1)
                            Text("From \(BlitzTimeStepper.label(overlay.start)) · \(BlitzTimeStepper.label(overlay.end - overlay.start)) long · \(overlay.style.preset.displayName)")
                                .font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .contentShape(.rect)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: selected?.id == overlay.id))
                .contextMenu { BlitzContextMenuItems(entries: actions(overlay)) }
                .accessibilityLabel("Edit \(overlay.text)")
            }
        }
    }

    private func actions(_ overlay: TextOverlay) -> [BlitzMenuEntry] {
        [
            .item(.init(title: "Play", systemImage: "play") { playback.play(from: overlay.start) }),
            .item(.init(title: "Delete", systemImage: BlitzSymbols.delete, isDestructive: true) { remove(overlay) })
        ]
    }

    private struct Field {
        let text: Binding<String>
        let placeholder: String
    }

    private func textField(_ field: Field) -> some View {
        TextField(field.placeholder, text: field.text, axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.plain)
            .font(BlitzType.section)
            .padding(12)
            .blitzFieldChrome(isFocused: isTextFocused)
            .focused($isTextFocused)
            .accessibilityLabel("Overlay text")
    }

    private struct StyleChoices {
        let selection: TextOverlayPreset
        let text: String
        let choose: (TextOverlayPreset) -> Void
    }

    private func styleChoices(_ request: StyleChoices) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(TextOverlayPreset.allCases, id: \.self) { preset in
                BlitzVisualChoice(configuration: .init(
                    title: preset.displayName,
                    help: "\(preset.displayName). Preview its look and position on your video.",
                    isSelected: request.selection == preset,
                    action: { request.choose(preset) },
                    preview: {
                        EditorTextStylePreview(configuration: .init(
                            preset: preset, text: request.text,
                            source: configuration.preview, scene: configuration.scene, layout: configuration.layout
                        ))
                    }
                ))
            }
        }
    }

    private func select(_ overlay: TextOverlay) {
        configuration.selectedID.wrappedValue = overlay.id
        error = nil
        playback.pauseForEditing()
        playback.seek(to: overlay.start + min(0.3, (overlay.end - overlay.start) / 2))
    }

    private func addText() {
        guard let overlay = TextOverlayEditing.newOverlay(.init(
            text: newText, preset: newPreset, time: playback.currentTime, duration: duration
        )) else { return }
        var updated = edits
        updated.textOverlays.append(overlay)
        guard apply(.init(edits: updated, actionName: "Add Text")) else { return }
        newText = ""
        select(overlay)
    }

    private func remove(_ overlay: TextOverlay) {
        if overlay.id == editTextID { pendingText?.cancel(); pendingText = nil }
        var updated = edits
        updated.textOverlays.removeAll { $0.id == overlay.id }
        if apply(.init(edits: updated, actionName: "Remove Text")), configuration.selectedID.wrappedValue == overlay.id {
            configuration.selectedID.wrappedValue = nil
        }
    }

    private func syncEditText() {
        editTextID = selected?.id
        editText = selected?.text ?? ""
    }

    private func scheduleTextSave() {
        guard let id = editTextID, edits.textOverlays.first(where: { $0.id == id })?.text != editText else { return }
        pendingText?.cancel()
        pendingText = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flushText()
        }
    }

    private func flushText() {
        pendingText?.cancel()
        pendingText = nil
        guard let id = editTextID, let overlay = edits.textOverlays.first(where: { $0.id == id }),
              overlay.text != editText.trimmingCharacters(in: .whitespacesAndNewlines),
              let changed = TextOverlayEditing.retexted(.init(overlay: overlay, text: editText)) else { return }
        update(.init(overlay: changed, actionName: "Edit Text"))
    }

    private struct OverlayUpdate {
        let overlay: TextOverlay
        let actionName: String
    }

    @discardableResult
    private func update(_ request: OverlayUpdate) -> Bool {
        guard let index = edits.textOverlays.firstIndex(where: { $0.id == request.overlay.id }),
              edits.textOverlays[index] != request.overlay else { return false }
        var updated = edits
        updated.textOverlays[index] = request.overlay
        return apply(.init(edits: updated, actionName: request.actionName))
    }

    private func apply(_ change: EditorTimelineEditsChange) -> Bool {
        playback.pauseForEditing()
        guard configuration.vm.applyOutputTextEdits(change) else {
            error = configuration.vm.detailMessage
            return false
        }
        error = nil
        return true
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
