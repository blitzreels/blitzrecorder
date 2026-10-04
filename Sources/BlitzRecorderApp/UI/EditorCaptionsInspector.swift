import SwiftUI

struct EditorCaptionsInspector: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let transcript: RecordingTranscript?
    }

    let configuration: Configuration
    @State private var isGenerating = false
    @State private var pendingProject: String?
    @State private var error: String?
    @State private var selectedID: UUID?
    @State private var draft = ""
    @State private var showsReplaceConfirmation = false

    private var project: RecordingProject? { configuration.vm.editorProject }
    private var track: CaptionTrack { project?.edits.captions ?? .empty }
    private var controller: LocalTranscriptionController { configuration.vm.transcriptionController }
    private var status: TranscriptionJobStatus { controller.jobStatuses[project?.projectPath ?? ""] ?? .notGenerated }

    var body: some View {
        EditorInspectorPane(configuration: .init(
            title: "Captions",
            detail: "Transcribe on this Mac. Captions appear in your preview and exported video.",
            showsFooter: true,
            content: {
                if !track.cues.isEmpty {
                    Toggle("Show captions", isOn: binding(\.isEnabled))
                        .toggleStyle(.blitzSwitch)
                        .help("Show or hide captions in preview and every export. Your caption text stays saved.")
                }
                appearance
                if !track.cues.isEmpty { captionList }
            },
            footer: { footer }
        ))
        .onChange(of: configuration.transcript) { generateWhenReady() }
        .onChange(of: status) { generateWhenReady() }
        .onChange(of: project?.projectPath) {
            pendingProject = nil
            selectedID = nil
            error = nil
        }
        .onChange(of: track.cues) {
            if let selectedID, let cue = track.cues.first(where: { $0.id == selectedID }) { draft = cue.text }
            else { selectedID = nil }
        }
        .confirmationDialog("Replace caption text from the transcript?", isPresented: $showsReplaceConfirmation) {
            Button("Replace captions", role: .destructive, action: requestGeneration)
        } message: {
            Text("This replaces your caption corrections. Style stays the same. You can undo the replacement.")
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(CaptionStyle.allCases, id: \.self) { style in
                    BlitzVisualChoice(configuration: .init(
                        title: style.title,
                        help: style == .outline ? "White text with a black border" : "White text on a dark background",
                        isSelected: track.style == style,
                        action: { binding(\.style).wrappedValue = style },
                        preview: { CaptionStylePreview(style: style) }
                    ))
                }
            }
            Text("Size").font(BlitzType.section)
            BlitzSegmentedPicker(configuration: .init(title: "Caption size", options: CaptionSize.allCases,
                selection: binding(\.size), label: { $0.title }))
            Text("Position").font(BlitzType.section)
            BlitzSegmentedPicker(configuration: .init(title: "Caption position", options: CaptionPosition.allCases,
                selection: binding(\.position), label: { $0.title }))
            Toggle("Shadow", isOn: binding(\.shadow)).toggleStyle(.blitzSwitch)
        }
    }

    private var captionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzInspectorHeading(configuration: .init(title: "Caption text",
                detail: track.cues.count == 1 ? "1 caption" : "\(track.cues.count) captions"))
            if selectedID != nil {
                TextField("Caption text", text: $draft, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .font(BlitzType.body)
                    .padding(10)
                    .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
                    .accessibilityLabel("Edit caption text")
                    .onChange(of: draft) { _, value in
                        if value.count > 160 { draft = String(value.prefix(160)) }
                    }
                HStack {
                    Button("Cancel") { selectedID = nil }.blitzButton(.secondary)
                    Button("Save text", action: saveText).blitzButton(.accent)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(track.cues) { cue in
                    Button {
                        selectedID = cue.id
                        draft = cue.text
                        configuration.playback.pauseForEditing()
                        configuration.playback.seek(to: cue.start)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cue.text).font(BlitzType.body).lineLimit(2)
                            Text("\(SilenceTime.label(cue.start))–\(SilenceTime.label(cue.end))")
                                .font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(BlitzSelectionButtonStyle(isSelected: selectedID == cue.id))
                    .help("Edit this caption. Times refer to the original recording.")
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if let error {
            Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.recordRed)
                .fixedSize(horizontal: false, vertical: true)
        }
        if isGenerating {
            ProgressView("Preparing captions…").font(BlitzType.body)
        } else if status.isRunning {
            TranscriptionActivityView(configuration: .init(status: status,
                detail: controller.jobDetails[project?.projectPath ?? ""],
                startedAt: controller.jobStartedAt[project?.projectPath ?? ""]))
            ProgressView().progressViewStyle(.linear)
        } else if case .downloading(let progress, let phase) = controller.modelState, pendingProject != nil {
            Text("Downloading speech model · \(phase)").font(BlitzType.body)
            ProgressView(value: progress)
        } else if status == .noAudio {
            Text("This video has no audio track to transcribe.").font(BlitzType.body)
        } else {
            if case .failed(let message) = status {
                Text(message).font(BlitzType.caption).foregroundStyle(BlitzUI.recordRed)
            }
            if case .failed(let message) = controller.modelState, pendingProject != nil {
                Text(message).font(BlitzType.caption).foregroundStyle(BlitzUI.recordRed)
            }
            Button {
                if track.cues.isEmpty { requestGeneration() } else { showsReplaceConfirmation = true }
            } label: {
                Label(track.cues.isEmpty ? "Generate captions" : "Regenerate captions", systemImage: "captions.bubble")
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(track.cues.isEmpty ? .accent : .secondary)
            .disabled(project == nil)
            if configuration.transcript == nil, !controller.modelState.isReady {
                Text("Downloads a speech model once. Your video and audio stay on this Mac.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
        }
        Text("Saved in this project · ⌘Z to undo")
            .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CaptionTrack, Value>) -> Binding<Value> {
        Binding(get: { track[keyPath: keyPath] }, set: { value in
            var updated = track
            updated[keyPath: keyPath] = value
            apply(.init(track: updated, actionName: "Change Captions"))
        })
    }

    private struct Change {
        let track: CaptionTrack
        let actionName: String
    }

    private func apply(_ change: Change) {
        guard var edits = configuration.vm.lastExportedProject?.edits else { return }
        edits.captions = change.track
        configuration.playback.pauseForEditing()
        error = configuration.vm.applyTimelineEdits(.init(edits: edits, actionName: change.actionName))
            ? nil : configuration.vm.detailMessage
    }

    private func requestGeneration() {
        error = nil
        guard let project else { return }
        if let transcript = configuration.transcript { generate(transcript) }
        else {
            pendingProject = project.projectPath
            controller.retry(.project(URL(fileURLWithPath: project.projectPath)))
        }
    }

    private func generateWhenReady() {
        guard pendingProject == project?.projectPath, let transcript = configuration.transcript,
              !status.isRunning else { return }
        pendingProject = nil
        generate(transcript)
    }

    private func generate(_ transcript: RecordingTranscript) {
        guard !isGenerating, let path = project?.projectPath else { return }
        isGenerating = true
        Task { @MainActor in
            let cues = await Task.detached(priority: .userInitiated) { CaptionGenerator.cues(transcript) }.value
            isGenerating = false
            guard configuration.vm.editorProject?.projectPath == path else { return }
            guard !cues.isEmpty else { error = "No speech was found in this transcript."; return }
            var updated = configuration.vm.editorProject?.edits.captions ?? .empty
            updated.cues = cues
            updated.isEnabled = true
            apply(.init(track: updated, actionName: "Generate Captions"))
        }
    }

    private func saveText() {
        guard let selectedID, let index = track.cues.firstIndex(where: { $0.id == selectedID }) else { return }
        var updated = track
        updated.cues[index].text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.cues[index].words = []
        apply(.init(track: updated, actionName: "Edit Caption Text"))
        if error == nil { self.selectedID = nil }
    }
}

struct CaptionStylePreview: View {
    let style: CaptionStyle

    var body: some View {
        ZStack {
            BlitzUI.cardFill
            if let sprite {
                Image(decorative: sprite.image, scale: 1).resizable().aspectRatio(contentMode: .fit).padding(5)
            }
        }
    }

    private var sprite: CaptionSprite? {
        var track = CaptionTrack.empty
        track.style = style
        return CaptionRenderer.sprite(.init(.init(
            cue: .init(id: UUID(), start: 0, end: 1, text: "Your words", words: []),
            track: track, canvasSize: CGSize(width: 640, height: 360))))
    }
}
