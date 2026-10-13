import SwiftUI

struct RecorderSceneStrip: View {
    enum Density {
        case regular
        case compact

        var showsTitle: Bool { self == .regular }
        var tileWidth: CGFloat { self == .regular ? 96 : 88 }
        var thumbnailSize: CGSize { self == .regular ? CGSize(width: 58, height: 34) : CGSize(width: 52, height: 30) }
    }

    @Bindable var vm: RecorderViewModel
    let density: Density

    private var isLive: Bool { vm.state == .recording || vm.state == .paused }

    var body: some View {
        HStack(spacing: 6) {
            if density.showsTitle {
                Text("Scenes")
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.tertiaryText)
                    .fixedSize()
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }

            ViewThatFits(in: .horizontal) {
                sceneTiles
                    .fixedSize(horizontal: true, vertical: false)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        sceneTiles
                    }
                    .scrollIndicators(.never)
                    .frame(height: Tile.height)
                    .onAppear {
                        if let sceneID = vm.selectedSceneID { proxy.scrollTo(sceneID, anchor: .center) }
                    }
                    .onChange(of: vm.selectedSceneID) { _, sceneID in
                        if let sceneID { proxy.scrollTo(sceneID, anchor: .center) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenes")
    }

    private var sceneTiles: some View {
        HStack(spacing: 4) {
            ForEach(Array(vm.currentScenes.enumerated()), id: \.element.id) { index, scene in
                tile(.init(scene: scene, index: index))
                    .id(scene.id)
            }
        }
    }

    private struct Tile {
        static let height: CGFloat = 64

        let scene: RecordingSceneDefinition
        let index: Int

        var shortcutDigit: Character? {
            index < 9 ? Character("\(index + 1)") : nil
        }
    }

    private func tile(_ tile: Tile) -> some View {
        let scene = tile.scene
        let isSelected = vm.selectedSceneID == scene.id
        return Button {
            vm.selectScene(scene.id)
            vm.selectLayoutInspector()
        } label: {
            VStack(spacing: 6) {
                BlitzSceneLayoutThumbnail(
                    layout: scene.layout,
                    sceneLayout: vm.sceneLayout(scene),
                    visibleSources: vm.sceneVisibleSources(scene)
                )
                .frame(width: density.thumbnailSize.width, height: density.thumbnailSize.height)
                .opacity(isSelected ? 1 : 0.62)

                HStack(spacing: 4) {
                    if isSelected && isLive {
                        BlitzStatusDot(tone: .recording, diameter: 6)
                            .accessibilityHidden(true)
                    }
                    Text(vm.sceneLabel(scene))
                        .font(BlitzType.captionEmphasis)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: density.tileWidth, height: Tile.height)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
        .disabled(!vm.canSwitchScene && !isSelected)
        .pointingHandCursor()
        .accessibilityLabel("Scene \(tile.index + 1), \(vm.sceneLabel(scene))\(isSelected && isLive ? ", live" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .keyboardShortcut(tile.shortcutDigit.map { KeyboardShortcut(KeyEquivalent($0), modifiers: .command) })
        .help(helpText(tile))
        .contextMenu {
            Button("Reset Scene") {
                vm.selectScene(scene.id)
                vm.resetSceneLayout()
            }
            .disabled(!vm.canEditScene)
        }
    }

    private func helpText(_ tile: Tile) -> String {
        let shortcut = tile.shortcutDigit.map { " (⌘\(String($0)))" } ?? ""
        let label = vm.sceneLabel(tile.scene)
        let remembers = "Move the camera anytime, even while recording. This scene remembers where you put it."
        if isLive {
            return "Cut to \(label)\(shortcut). \(remembers)"
        }
        return "Start on \(label)\(shortcut). \(remembers)"
    }
}
