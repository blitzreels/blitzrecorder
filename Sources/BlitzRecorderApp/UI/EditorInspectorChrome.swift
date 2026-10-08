import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorInspectorTabBar: View {
    @Binding var selection: EditorInspectorTab

    private let tabs: [EditorInspectorTab] = [.layout, .silence, .captions, .text, .zoom, .privacy, .audio]

    var body: some View {
        BlitzToolTabBar(configuration: .init(
            title: "Editor tools",
            options: tabs,
            selection: selection,
            label: { $0.rawValue },
            symbolName: { $0.systemImage },
            help: { $0 == .layout ? "Scene layout and canvas" : $0.rawValue },
            isOptionEnabled: { _ in true },
            select: { selection = $0 }
        ))
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
                        .font(BlitzType.section)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(backgroundMusic == nil ? "Optional" : "Loops through the full export")
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.secondaryText)
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
                    Label(backgroundMusic == nil ? "Choose…" : "Remove",
                          systemImage: backgroundMusic == nil ? "plus" : "trash.fill")
                }
                .blitzButton(.secondary)
                .controlSize(.small)
                .accessibilityLabel(backgroundMusic == nil ? "Choose background music" : "Remove background music")
                .help(backgroundMusic == nil ? "Choose an audio file" : "Remove background music")
            }

            if backgroundMusic != nil {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.1")
                        .font(BlitzType.glyph(10))
                        .foregroundStyle(BlitzUI.secondaryText)
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
                        .font(BlitzType.captionEmphasis.monospacedDigit())
                        .monospacedDigit()
                        .foregroundStyle(BlitzUI.supportingText)
                        .frame(width: 36, alignment: .trailing)
                }

                Text("Mixed during export with a smooth fade-out.")
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
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
