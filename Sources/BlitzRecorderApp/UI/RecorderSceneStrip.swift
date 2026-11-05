import SwiftUI

struct RecorderSceneStrip: View {
    enum Density {
        case labeled
        case pictures

        var showsTitle: Bool { self == .labeled }
    }

    static let wellPadding: CGFloat = 3
    static let tileHeight: CGFloat = BlitzControlMetrics.prominentDockHeight - wellPadding * 2

    @Bindable var vm: RecorderViewModel
    let density: Density

    private var isLive: Bool { vm.state == .recording || vm.state == .paused }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            sceneTiles
                .fixedSize(horizontal: true, vertical: false)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    sceneTiles
                }
                .scrollIndicators(.never)
                .frame(height: Self.tileHeight)
                .onAppear {
                    if let sceneID = vm.selectedSceneID { proxy.scrollTo(sceneID, anchor: .center) }
                }
                .onChange(of: vm.selectedSceneID) { _, sceneID in
                    if let sceneID { proxy.scrollTo(sceneID, anchor: .center) }
                }
            }
        }
        .padding(Self.wellPadding)
        .background(BlitzUI.insetWell, in: .rect(cornerRadius: BlitzControlMetrics.dockRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenes")
    }

    private var sceneTiles: some View {
        HStack(spacing: 2) {
            ForEach(Array(vm.currentScenes.enumerated()), id: \.element.id) { index, scene in
                tile(.init(scene: scene, index: index))
                    .id(scene.id)
            }
        }
    }

    private struct Tile {
        let scene: RecordingSceneDefinition
        let index: Int

        var shortcutDigit: Character? {
            index < 9 ? Character("\(index + 1)") : nil
        }

        func thumbnailSize(showsTitle: Bool) -> CGSize {
            let height: CGFloat = showsTitle ? 26 : 34
            return CGSize(width: min(height * scene.layout.aspectRatio, 56), height: height)
        }
    }

    private func tile(_ tile: Tile) -> some View {
        let scene = tile.scene
        let isSelected = vm.selectedSceneID == scene.id
        let showsLiveDot = isSelected && isLive
        let thumbnailSize = tile.thumbnailSize(showsTitle: density.showsTitle)
        return Button {
            vm.selectScene(scene.id)
            vm.selectLayoutInspector()
        } label: {
            VStack(spacing: 3) {
                BlitzSceneLayoutThumbnail(
                    layout: scene.layout,
                    sceneLayout: vm.sceneLayout(scene),
                    visibleSources: vm.sceneVisibleSources(scene)
                )
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .opacity(isSelected ? 1 : 0.8)
                .overlay(alignment: .topTrailing) {
                    if showsLiveDot && !density.showsTitle {
                        BlitzStatusDot(tone: .recording, diameter: 6)
                            .offset(x: 3, y: -3)
                            .accessibilityHidden(true)
                    }
                }

                if density.showsTitle {
                    HStack(spacing: 4) {
                        if showsLiveDot {
                            BlitzStatusDot(tone: .recording, diameter: 5)
                                .accessibilityHidden(true)
                        }
                        Text(vm.sceneLabel(scene))
                            .font(BlitzType.control(11))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: Self.tileHeight, minHeight: Self.tileHeight, maxHeight: Self.tileHeight)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
        .disabled(!vm.canSwitchScene && !isSelected)
        .accessibilityLabel("Scene \(tile.index + 1), \(vm.sceneLabel(scene))\(showsLiveDot ? ", live" : "")")
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
