import SwiftUI

struct EditorAudioInspector: View {
    struct Configuration {
        let vm: RecorderViewModel
        let playback: EditorPlaybackController
    }

    let configuration: Configuration
    @State private var strength = 0.65
    @State private var error: String?
    private var settings: VoiceCleanupSettings { configuration.vm.lastExportedProject?.edits.voiceCleanup ?? .disabled }
    private var hasMicrophone: Bool {
        configuration.vm.lastExportedProject?.sources.contains { $0.role == "microphone" && $0.exists } == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Voice cleanup").font(.headline)
                Text("Reduce steady background noise in the microphone track. Processing stays on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
                Toggle("Clean up microphone", isOn: Binding(get: { settings.isEnabled }, set: { value in
                    var settings = settings; settings.isEnabled = value; save(settings)
                })).toggleStyle(.blitzSwitch).disabled(!hasMicrophone)
                if !hasMicrophone { Text("This take has no microphone source.").font(.caption) }
                if settings.isEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Noise reduction · \(Int(strength * 100))%")
                        Slider(value: $strength, in: 0...1, onEditingChanged: { editing in
                            if !editing { var settings = settings; settings.strength = strength; save(settings) }
                        }).accessibilityLabel("Noise reduction strength")
                        Text("Use a lower strength if speech sounds thin.").font(.caption).foregroundStyle(BlitzUI.secondaryText)
                    }
                    Toggle("Even out speech volume", isOn: Binding(get: { settings.normalizesSpeech }, set: { value in
                        var settings = settings; settings.normalizesSpeech = value; save(settings)
                    })).toggleStyle(.blitzSwitch)
                    Toggle("Listen to original", isOn: Binding(get: { configuration.playback.bypassesVoiceCleanup }, set: { value in
                        guard let project = configuration.vm.editorProject else { return }
                        Task { await configuration.playback.compareVoiceCleanup(.init(
                            bypassed: value, project: project, settings: configuration.vm.settings)) }
                    })).toggleStyle(.blitzSwitch)
                    Text("Comparison affects preview only. Exports use your saved cleanup settings.")
                        .font(.caption).foregroundStyle(BlitzUI.secondaryText)
                }
                Divider()
                Toggle("Lower music during speech", isOn: Binding(get: { settings.ducksMusic }, set: { value in
                    var settings = settings; settings.ducksMusic = value; save(settings)
                })).toggleStyle(.blitzSwitch)
                Text("Choose background music below. Its volume returns between spoken sections.")
                    .font(.caption).foregroundStyle(BlitzUI.secondaryText)
                if let error { Text(error).foregroundStyle(BlitzUI.warning) }
            }.padding(14)
        }
        .task(id: settings.strength) { strength = settings.strength }
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
