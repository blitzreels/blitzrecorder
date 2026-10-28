import SwiftUI

struct EditorAudioInspector<Music: View>: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
        let hasMusic: Bool
        @ViewBuilder let music: () -> Music
    }

    let configuration: Configuration
    @State private var error: String?
    private var settings: VoiceCleanupSettings { configuration.vm.lastExportedProject?.edits.voiceCleanup ?? .disabled }
    private var hasMicrophone: Bool {
        configuration.vm.lastExportedProject?.sources.contains { $0.role == "microphone" && $0.exists } == true
    }
    private var volumeSources: [CaptureSource] {
        [CaptureSource.microphone, .systemAudio].filter { configuration.playback.muteableSources.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
            if let project = configuration.vm.lastExportedProject, project.cameraAngles.count >= 2 {
                EditorInspectorSection(configuration: .init(title: "Cameras", content: { cameras(project) }))
            }
            if !volumeSources.isEmpty {
                EditorInspectorSection(configuration: .init(title: "Volume", content: {
                    ForEach(volumeSources, id: \.self) { source in
                        EditorTrackVolumeSlider(configuration: .init(
                            title: source == .microphone ? "Microphone" : "Mac audio",
                            source: source, playback: configuration.playback,
                            onCommit: configuration.vm.changeEditorTrackVolume))
                    }
                }))
            }
            if hasMicrophone {
                EditorInspectorSection(configuration: .init(title: "Voice cleanup", content: { cleanup }))
            }
            EditorInspectorSection(configuration: .init(title: "Music", content: {
                configuration.music()
                if configuration.hasMusic {
                    Toggle("Lower music while you talk", isOn: Binding(get: { settings.ducksMusic }, set: { value in
                        var settings = settings; settings.ducksMusic = value; save(settings)
                    }))
                    .toggleStyle(.blitzSwitch)
                    .help("Music gets quieter while you talk and comes back between sentences.")
                }
            }))
            if let error { Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Which camera's sound plays, and how each camera was synced. The other cameras' sound stays silent.
    private func cameras(_ project: RecordingProject) -> some View {
        let switching = configuration.vm.editorSoundSwitch
        return VStack(alignment: .leading, spacing: 10) {
            BlitzSegmentedPicker(configuration: .init(
                title: "Sound from", options: project.cameraAngles.map(\.role),
                selection: Binding(get: { switching ?? project.programAudioRole ?? CameraFeeds.mainRole },
                                   set: configuration.vm.useProgramAudio),
                label: { project.cameraAngles.record(role: $0)?.title ?? $0 }
            ))
            Text(switching == nil ? "The other cameras stay silent." : "Preparing that camera's sound…")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(project.cameraAngles, id: \.role) { angle in
                    HStack(spacing: 8) {
                        Text(angle.title).font(BlitzType.body).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(angle.syncStatusText).font(BlitzType.caption)
                            .foregroundStyle(angle.needsReview ? BlitzUI.warning : BlitzUI.secondaryText)
                    }
                }
            }
        }
    }

    private var cleanup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Clean up microphone", isOn: Binding(get: { settings.isEnabled }, set: { value in
                var settings = settings; settings.isEnabled = value; save(settings)
            }))
            .toggleStyle(.blitzSwitch)
            Text("Removes background noise from your voice. Your video isn't changed.")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if settings.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    BlitzSegmentedPicker(configuration: .init(
                        title: "Noise reduction", options: VoiceCleanupLevel.available,
                        selection: Binding(get: { VoiceCleanupLevel(settings: settings) }, set: { level in
                            save(level.applied(to: settings))
                        }),
                        label: \.title
                    ))
                    Text(VoiceCleanupLevel(settings: settings).detail)
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                cleanupStatus
                if configuration.playback.audioProgress == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        BlitzSegmentedPicker(configuration: .init(
                            title: "Compare", options: [true, false],
                            selection: Binding(get: { configuration.playback.bypassesVoiceCleanup },
                                               set: configuration.playback.setVoiceCleanupBypassed),
                            label: { $0 ? "Before" : "After" }
                        ))
                        Text("Switch while playing to hear the difference. Exports always use After.")
                            .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    }
                }
                Toggle("Even out speech volume", isOn: Binding(get: { settings.normalizesSpeech }, set: { value in
                    var settings = settings; settings.normalizesSpeech = value; save(settings)
                }))
                .toggleStyle(.blitzSwitch)
            }
        }
    }

    /// Fixed height so the line can change between working and done without moving the controls below it.
    private var cleanupStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = configuration.playback.audioProgress {
                Text("Cleaning your voice… \(Int((progress * 100).rounded()))%")
                    .font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.supportingText)
                ProgressView(value: progress).progressViewStyle(.linear).tint(BlitzUI.accent)
            } else if configuration.playback.heardMicrophoneURL == nil {
                Label("Getting ready…", systemImage: "hourglass")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.supportingText)
            } else {
                Label(configuration.playback.bypassesVoiceCleanup
                      ? "You're hearing the original voice"
                      : "Done · you're hearing the cleaned voice",
                      systemImage: configuration.playback.bypassesVoiceCleanup ? "waveform" : "checkmark.circle.fill")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.supportingText)
            }
        }
        .frame(height: 34, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: configuration.playback.audioProgress == nil)
    }

    private func save(_ settings: VoiceCleanupSettings) {
        guard var edits = configuration.vm.lastExportedProject?.edits else { return }
        configuration.playback.pauseForEditing()
        edits.voiceCleanup = settings
        if !configuration.vm.applyTimelineEdits(.init(edits: edits, actionName: "Change Voice Cleanup")) {
            error = configuration.vm.detailMessage
        }
    }
}
