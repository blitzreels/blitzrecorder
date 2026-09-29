import SwiftUI

struct RecorderSceneStrip: View {
    @Bindable var vm: RecorderViewModel
    @State private var renamingSceneID: UUID?
    @State private var draftName = ""
    @State private var deletingScene: RecordingSceneDefinition?

    private var isLive: Bool { vm.state == .recording || vm.state == .paused }

    private var livePreview: BlitzScenePreview? {
        let frames = vm.liveSceneThumbnails
        guard frames.screen != nil || frames.camera != nil else { return nil }
        return BlitzScenePreview(screen: frames.screen, camera: frames.camera, background: vm.settings.canvasBackgroundStyle)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(vm.currentScenes.enumerated()), id: \.element.id) { index, scene in
                tile(.init(scene: scene, index: index))
            }
        }
        .padding(4)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenes")
        .confirmationDialog(
            "Delete \(deletingScene?.name ?? "scene")?",
            isPresented: Binding(get: { deletingScene != nil }, set: { if !$0 { deletingScene = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete scene", role: .destructive) {
                if let deletingScene { vm.deleteScene(deletingScene.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the scene and its layout.")
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
        } label: {
            VStack(spacing: 5) {
                BlitzSceneLayoutThumbnail(
                    layout: scene.layout,
                    sceneLayout: scene.snapshot.sceneLayout,
                    visibleSources: scene.snapshot.enabledVideoSources
                        .intersection(vm.settings.enabledSources)
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
        .popover(isPresented: renameBinding(scene), arrowEdge: .top) {
            renameField(scene)
        }
        .contextMenu {
            Group {
                Button("Rename…") {
                    draftName = scene.name
                    renamingSceneID = scene.id
                }
                Button("Duplicate") {
                    vm.selectScene(scene.id)
                    vm.duplicateSelectedScene()
                }
                Button("Reset layout") {
                    vm.selectScene(scene.id)
                    vm.resetSceneLayout()
                }
                Divider()
                Button("Delete…", role: .destructive) {
                    deletingScene = scene
                }
                .disabled(vm.currentScenes.count <= 1)
            }
            .disabled(!vm.canEditScene)
        }
    }

    private func renameBinding(_ scene: RecordingSceneDefinition) -> Binding<Bool> {
        Binding(
            get: { renamingSceneID == scene.id },
            set: { if !$0 { renamingSceneID = nil } }
        )
    }

    private func renameField(_ scene: RecordingSceneDefinition) -> some View {
        HStack(spacing: 8) {
            TextField("Scene name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { commitRename(scene) }
            Button("Save") { commitRename(scene) }
                .blitzButton(.accent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .preferredColorScheme(.dark)
    }

    private func commitRename(_ scene: RecordingSceneDefinition) {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != scene.name {
            vm.renameScene(scene.id, to: name)
        }
        renamingSceneID = nil
    }
}
