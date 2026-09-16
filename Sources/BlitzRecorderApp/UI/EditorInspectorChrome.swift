import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorInspectorTabBar: View {
    @Binding var selection: EditorInspectorTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach([EditorInspectorTab.layout, .silence, .text, .zoom, .privacy, .audio], id: \.self) { tab in
                BlitzTab(configuration: .init(
                    title: tab.rawValue,
                    symbolName: tab.systemImage,
                    symbolPlacement: .above,
                    isSelected: selection == tab,
                    expands: true,
                    action: { selection = tab }
                ))
                .help(tab == .layout ? "Scene layout and canvas" : tab.rawValue)
            }
        }
        .controlSize(.mini)
        .padding(6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor tools")
    }
}

struct EditorBackgroundMusicControl: View {
    @Binding var backgroundMusic: ExportBackgroundMusic?
    @Binding var backgroundMusicBookmarkData: Data?
    let persist: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BlitzIconTile(symbolName: "music.note", isSelected: backgroundMusic != nil, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backgroundMusic?.url.lastPathComponent ?? "Background music")
                        .font(.system(size: 11.5, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(backgroundMusic == nil ? "Optional" : "Loops through the full export")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                Button {
                    if backgroundMusic == nil {
                        chooseBackgroundMusic()
                    } else {
                        backgroundMusic = nil
                        backgroundMusicBookmarkData = nil
                        persist("Remove Background Music")
                    }
                } label: {
                    Text(backgroundMusic == nil ? "Choose…" : "Remove")
                }
                .blitzButton(.secondary)
                .controlSize(.small)
                .accessibilityLabel(backgroundMusic == nil ? "Choose background music" : "Remove background music")
                .help(backgroundMusic == nil ? "Choose an audio file" : "Remove background music")
            }

            if backgroundMusic != nil {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.1")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                    Slider(
                        value: volumeBinding,
                        in: 0...1,
                        step: 0.01,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                persist("Change Music Volume")
                            }
                        }
                    )
                    .controlSize(.small)
                    .tint(BlitzUI.mint)
                    Text(volumeLabel)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 36, alignment: .trailing)
                }

                Text("Mixed during export with a smooth fade-out.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(10)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
    }

    var volumeLabel: String {
        Self.volumeLabel(for: backgroundMusic)
    }

    static func volumeLabel(for music: ExportBackgroundMusic?) -> String {
        "\(Int(((music?.volume ?? 0) * 100).rounded()))%"
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { backgroundMusic?.volume ?? 0.18 },
            set: { volume in
                guard let selection = backgroundMusic else { return }
                backgroundMusic = ExportBackgroundMusic(
                    url: selection.url,
                    volume: min(1, max(0, volume))
                )
            }
        )
    }

    private func chooseBackgroundMusic() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = "Use Music"
        panel.message = "Choose background music to loop under this export."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backgroundMusic = ExportBackgroundMusic(url: url, volume: 0.18)
        backgroundMusicBookmarkData = RecordingSettingsStore.bookmarkData(for: url)
        persist("Add Background Music")
    }
}
