import SwiftUI

struct EditorTrackVolumeControl: View {
    struct Configuration {
        let title: String
        let source: CaptureSource
        let playback: EditorPlaybackController
        let onCommit: (EditorTrackVolumeChange) -> Bool
    }

    let configuration: Configuration
    @State private var showsVolume = false

    var body: some View {
        Button("\(Int((configuration.playback.audioLevels.volume(for: configuration.source) * 100).rounded()))%") {
            showsVolume.toggle()
        }
        .monospacedDigit()
        .blitzButton(.quiet)
        .controlSize(.mini)
        .accessibilityLabel("\(configuration.title) volume")
        .accessibilityValue("\(Int((configuration.playback.audioLevels.volume(for: configuration.source) * 100).rounded())) percent")
        .help("Adjust \(configuration.title) volume throughout playback and export")
        .popover(isPresented: $showsVolume, arrowEdge: .top) {
            EditorTrackVolumeSlider(configuration: configuration)
                .padding(16)
                .frame(width: 260)
        }
    }
}

struct EditorTrackVolumeSlider: View {
    let configuration: EditorTrackVolumeControl.Configuration
    @State private var startingVolume: Double?

    private var volume: Double { configuration.playback.audioLevels.volume(for: configuration.source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(configuration.title).font(BlitzType.label)
                Spacer()
                Text("\(Int((volume * 100).rounded()))%")
                    .font(BlitzType.captionEmphasis.monospacedDigit())
            }
            Slider(value: Binding(get: { volume }, set: { value in
                let previous = volume
                configuration.playback.setTrackVolume(.init(source: configuration.source, volume: value))
                if startingVolume == nil { commit(previous) }
            }), in: 0...1, onEditingChanged: { editing in
                if editing {
                    startingVolume = volume
                } else if let previous = startingVolume {
                    startingVolume = nil
                    commit(previous)
                }
            })
            .accessibilityLabel("\(configuration.title) volume")
            .accessibilityValue("\(Int((volume * 100).rounded())) percent")
            if configuration.playback.mutedSources.contains(configuration.source) {
                Text("Muted. Unmute this track to hear its saved level.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .onDisappear {
            if let previous = startingVolume {
                startingVolume = nil
                commit(previous)
            }
        }
    }

    private func commit(_ previous: Double) {
        guard volume != previous else { return }
        if !configuration.onCommit(.init(source: configuration.source, volume: volume)) {
            configuration.playback.setTrackVolume(.init(source: configuration.source, volume: previous))
        }
    }
}

extension RecorderViewModel {
    func changeEditorTrackVolume(_ change: EditorTrackVolumeChange) -> Bool {
        guard var state = editorProject?.editorState, change.volume.isFinite else { return false }
        var levels = state.audioLevels ?? .unity
        levels.setVolume(change)
        state.audioLevels = levels == .unity ? nil : levels
        let title = change.source == .microphone ? "Microphone" : "Mac Audio"
        return applyProjectEditorState(.init(editorState: state, actionName: "Change \(title) Volume"))
    }
}
