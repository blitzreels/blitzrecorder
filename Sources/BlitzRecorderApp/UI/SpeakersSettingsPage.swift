import SwiftUI

struct SpeakersSettingsPage: View {
    let projects: [RecordingProjectHistory.Entry]
    let openRecording: (RecordingProjectHistory.Entry) -> Void
    @State private var model = SpeakersSettingsModel()
    @State private var discovery = VoiceDiscoveryModel.shared
    @State private var section = Section.saved
    @State private var renamingID: UUID?
    @State private var forgetting: SavedSpeakerVoice?
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private enum Section: CaseIterable {
        case saved
        case review
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    SettingsPageHeader(.init(
                        title: "Speakers",
                        detail: "Familiar voices, recognized across your recordings.",
                        status: nil
                    ))
                    Button {
                        model.stop()
                        section = .review
                        discovery.start(projects)
                    } label: { Label("Detect voices", systemImage: "waveform.badge.magnifyingglass") }
                        .blitzButton(.accent)
                        .controlSize(.regular)
                        .fixedSize()
                        .disabled(projects.isEmpty || discovery.isScanning || discovery.isSaving || !discovery.preparingIDs.isEmpty)
                        .help("Scan your recordings for voices you haven’t saved. Runs on this Mac.")
                }
                .padding(.bottom, 4)

                BlitzSegmentedPicker(configuration: .init(
                    title: "Voice library", options: Section.allCases, selection: $section,
                    label: { $0 == .saved ? "Saved · \(model.profiles.count)" : "To review · \(discovery.voices.count)" }
                ))
                .controlSize(.regular)
                .fixedSize()

                if section == .review {
                    VoiceDiscoverySection(discovery: discovery, player: model, openRecording: openRecording)
                } else if !model.isLoaded {
                    ProgressView("Loading saved speakers…")
                } else if model.profiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No saved speakers yet").font(BlitzType.section)
                        Text("Open a transcript, click a speaker’s name, then choose Remember this voice on this Mac.")
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                    .settingsSurface()
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.profiles) { profile in
                            if profile.id != model.profiles.first?.id { SettingsRowDivider() }
                            speakerRow(profile)
                        }
                    }
                    .settingsSection(.init(
                        title: "\(model.profiles.count) saved \(model.profiles.count == 1 ? "voice" : "voices")",
                        detail: nil, systemImage: "waveform"
                    ))
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.warning)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Stored on this Mac", systemImage: "internaldrive")
                        .font(BlitzType.captionEmphasis)
                    Text("To add someone, click their name in a transcript and choose Remember this voice.")
                        .font(BlitzType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(BlitzUI.secondaryText)
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .task { await model.load(projects) }
        .onDisappear { model.stop() }
        .confirmationDialog(
            "Forget \(forgetting?.name ?? "this speaker")?",
            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
            titleVisibility: .visible, presenting: forgetting
        ) { profile in
            Button("Forget speaker", role: .destructive) { Task { await model.forget(profile.id) } }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: { _ in
            Text("Removes the saved voice and its audio sample from this Mac. Existing transcript names stay unchanged.")
        }
    }

    private func speakerRow(_ profile: SavedSpeakerVoice) -> some View {
        HStack(spacing: 14) {
            BlitzRemoteIcon(configuration: .init(
                name: profile.name, seed: profile.id.uuidString, imageURL: nil, size: 36, isCircle: false
            ))

            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name)
                    .font(BlitzType.headline)
                    .lineLimit(1)
                if model.preparingID == profile.id {
                    Text("Preparing voice sample…")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                } else if let preview = profile.preview, model.availableSamples.contains(profile.id) {
                    Text(preview.sourceTitle)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("Sample from \(preview.sourceTitle)")
                } else {
                    Text("No voice sample")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .help("Remember this voice again from a transcript to add a sample.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.preparingID == profile.id {
                ProgressView().controlSize(.small)
            } else if let preview = profile.preview, model.availableSamples.contains(profile.id) {
                samplePlayback(.init(profile: profile, preview: preview))
            }

            speakerMenu(profile)
        }
        .settingsRow()
        .padding(.vertical, 4)
        .popover(isPresented: Binding(
            get: { renamingID == profile.id }, set: { if !$0 { renamingID = nil } }
        ), arrowEdge: .bottom) { renameEditor(profile) }
        .contextMenu {
            Button("Rename…", systemImage: "pencil") { beginRename(profile) }
            Button("Forget speaker…", systemImage: "trash", role: .destructive) { forgetting = profile }
                .disabled(model.isSaving)
        }
    }

    private struct PlaybackConfiguration {
        let profile: SavedSpeakerVoice
        let preview: SavedSpeakerPreview
    }

    private func samplePlayback(_ configuration: PlaybackConfiguration) -> some View {
        let profile = configuration.profile
        let duration = configuration.preview.duration
        let isPlaying = model.playingID == profile.id
        return HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !isPlaying)) { _ in
                let elapsed = model.playbackTime(for: profile.id)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(MediaTimecode.label(.init(time: isPlaying ? elapsed : duration, duration: duration)))
                        .font(BlitzType.numeric)
                        .foregroundStyle(isPlaying ? BlitzUI.mint : BlitzUI.secondaryText)
                    ProgressView(value: min(elapsed / max(duration, 0.1), 1))
                        .progressViewStyle(.linear)
                        .tint(BlitzUI.mint)
                        .scaleEffect(x: 1, y: 0.5)
                        .frame(height: 2)
                        .opacity(isPlaying ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .frame(width: 36)
            }
            .accessibilityLabel("Sample duration")
            .accessibilityValue("\(Int(duration.rounded())) seconds")

            Button { Task { await model.togglePlayback(profile.id) } } label: {
                Label(isPlaying ? "Stop" : "Play sample", systemImage: isPlaying ? "stop.fill" : "play.fill")
                    .frame(width: 92)
            }
            .blitzButton(isPlaying ? .accent : .secondary)
            .controlSize(.regular)
            .accessibilityLabel("\(isPlaying ? "Stop" : "Play") \(profile.name)’s sample")
        }
        .fixedSize()
    }

    private func speakerMenu(_ profile: SavedSpeakerVoice) -> some View {
        BlitzOverflowMenu(configuration: .init(
            entries: [
                .item(.init(title: "Rename…", systemImage: "pencil", action: { beginRename(profile) })),
                .divider,
                .item(.init(title: "Forget speaker…", systemImage: "trash", isDestructive: true,
                            action: { forgetting = profile }))
            ],
            menuWidth: 200,
            placement: .inline,
            isBusy: false,
            accessibilityLabel: "Actions for \(profile.name)",
            help: "Rename or forget \(profile.name)"
        ))
        .controlSize(.regular)
        .disabled(model.isSaving)
    }

    private func beginRename(_ profile: SavedSpeakerVoice) {
        draftName = profile.name
        renamingID = profile.id
    }

    private func renameEditor(_ profile: SavedSpeakerVoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename saved speaker").font(BlitzType.section)
            TextField("Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(BlitzType.body)
                .focused($isNameFocused)
                .onSubmit { saveName(profile) }
                .padding(.horizontal, 10)
                .frame(height: BlitzControlMetrics.height(.regular))
                .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: BlitzControlMetrics.radius)
                        .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
                }
            Text("Used for future name suggestions. Existing transcripts keep their current names.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { renamingID = nil }
                    .blitzButton(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveName(profile) }
                    .blitzButton(.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValidName || model.isSaving)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(BlitzUI.panelBackground)
        .onAppear { isNameFocused = true }
    }

    private var isValidName: Bool {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != "You"
    }

    private func saveName(_ profile: SavedSpeakerVoice) {
        guard isValidName, !model.isSaving else { return }
        Task {
            if await model.rename(.init(id: profile.id, name: draftName)) { renamingID = nil }
        }
    }
}
