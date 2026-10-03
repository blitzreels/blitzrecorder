import SwiftUI

struct RecorderSceneStrip: View {
    @Bindable var vm: RecorderViewModel

    private var isLive: Bool { vm.state == .recording || vm.state == .paused }

    private var livePreview: BlitzScenePreview? {
        let frames = vm.liveSceneThumbnails
        guard frames.screen != nil || frames.camera != nil else { return nil }
        return BlitzScenePreview(screen: frames.screen, camera: frames.camera, background: vm.settings.canvasBackgroundStyle)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            sceneTiles
                .fixedSize(horizontal: true, vertical: false)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    sceneTiles
                }
                .frame(height: 72)
                .onAppear {
                    if let sceneID = vm.selectedSceneID { proxy.scrollTo(sceneID, anchor: .center) }
                }
                .onChange(of: vm.selectedSceneID) { _, sceneID in
                    if let sceneID { proxy.scrollTo(sceneID, anchor: .center) }
                }
            }
        }
        .padding(4)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
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
        let scene: RecordingSceneDefinition
        let index: Int

        var shortcut: KeyEquivalent? {
            index < 9 ? KeyEquivalent(Character("\(index + 1)")) : nil
        }
    }

    private func tile(_ tile: Tile) -> some View {
        let scene = tile.scene
        let isSelected = vm.selectedSceneID == scene.id
        return Button {
            vm.selectScene(scene.id)
            vm.selectLayoutInspector()
        } label: {
            VStack(spacing: 5) {
                BlitzSceneLayoutThumbnail(
                    layout: scene.layout,
                    sceneLayout: isSelected ? vm.settings.sceneLayout : scene.snapshot.sceneLayout,
                    visibleSources: vm.settings.enabledSources
                        .intersection([.screen, .camera])
                        .subtracting(scene.snapshot.hiddenVideoSources),
                    preview: livePreview
                )
                .frame(width: 58, height: 34)

                Text(scene.name)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 84, height: 60)
            .overlay(alignment: .topTrailing) {
                if isSelected && isLive {
                    Circle()
                        .fill(BlitzUI.recordRed)
                        .frame(width: 6, height: 6)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
        .disabled(!vm.canSwitchScene && !isSelected)
        .pointingHandCursor()
        .accessibilityLabel(scene.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .keyboardShortcut(tile.shortcut.map { KeyboardShortcut($0, modifiers: .command) })
        .help("\(isLive ? "Switch to" : "Use") \(scene.name)\(tile.shortcut == nil ? "" : " (⌘\(tile.index + 1))")")
        .contextMenu {
            Button("Reset layout") {
                vm.selectScene(scene.id)
                vm.resetSceneLayout()
            }
            .disabled(!vm.canEditScene)
        }
    }
}
