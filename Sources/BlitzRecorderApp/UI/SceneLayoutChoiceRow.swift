import AppKit
import SwiftUI

/// Layout choices drawn with the live screen, camera and background, like the background swatches.
struct SceneLayoutChoiceRow<Value: Hashable>: View {
    struct Configuration {
        let title: String
        let options: [Value]
        let selection: Value
        let label: (Value) -> String
        let help: (Value) -> String
        let sceneLayout: (Value) -> SceneLayout
        let layout: CaptureLayout
        let preview: BlitzScenePreview
        let select: (Value) -> Void
    }

    let configuration: Configuration

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BlitzUI.sectionLabel(configuration.title)
            HStack(alignment: .top, spacing: 6) {
                ForEach(configuration.options, id: \.self) { option in
                    SceneLayoutChoiceCard(configuration: .init(
                        title: configuration.label(option),
                        help: configuration.help(option),
                        layout: configuration.layout,
                        sceneLayout: configuration.sceneLayout(option),
                        preview: configuration.preview,
                        isSelected: option == configuration.selection,
                        action: { configuration.select(option) }
                    ))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(configuration.title)
    }
}

private struct SceneLayoutChoiceCard: View {
    struct Configuration {
        let title: String
        let help: String
        let layout: CaptureLayout
        let sceneLayout: SceneLayout
        let preview: BlitzScenePreview
        let isSelected: Bool
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    private static let radius: CGFloat = 9

    var body: some View {
        Button(action: configuration.action) {
            VStack(spacing: 5) {
                BlitzSceneLayoutThumbnail(
                    layout: configuration.layout,
                    sceneLayout: configuration.sceneLayout,
                    visibleSources: [.screen, .camera],
                    preview: configuration.preview
                )
                .aspectRatio(configuration.layout.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 118)
                .opacity(configuration.isSelected ? 1 : 0.7)
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                        .strokeBorder(ringColor, lineWidth: configuration.isSelected ? 2.5 : 2)
                }
                Text(configuration.title)
                    .font(BlitzType.footnote)
                    .foregroundStyle(configuration.isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: Self.radius, style: .continuous))
        }
        .buttonStyle(BlitzPressButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel(configuration.title)
        .accessibilityAddTraits(configuration.isSelected ? [.isSelected] : [])
        .help(configuration.help)
    }

    private var ringColor: Color {
        if configuration.isSelected { return BlitzUI.accent }
        return isHovering ? BlitzUI.tertiaryText : .clear
    }
}

/// Stills of the live screen and camera for layout choices. Refreshes every few seconds while the studio is in
/// front and idle, from the running previews when they have frames; with live previews off it takes one still.
struct ScenePicturesModifier: ViewModifier {
    @Bindable var vm: RecorderViewModel
    @Binding var pictures: ScenePictures

    private struct Refresh: Equatable {
        let binding: ScreenSourceBinding?
        let isActive: Bool
        let isLive: Bool
    }

    func body(content: Content) -> some View {
        content.task(id: Refresh(
            binding: vm.settings.screenSourceBinding,
            isActive: vm.isStudioOnScreen && vm.state == .idle,
            isLive: vm.isLivePreviewEnabled
        )) {
            guard vm.isStudioOnScreen, vm.state == .idle else { return }
            while !Task.isCancelled {
                vm.requestCameraStill { if let image = $0 { pictures.camera = image } }
                await refreshScreenPicture()
                guard vm.isLivePreviewEnabled else { return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refreshScreenPicture() async {
        let screenPreview = vm.previewStage.screenPreview
        if screenPreview.showsLiveFrames {
            screenPreview.requestStillFrame { if let image = $0 { pictures.screen = image } }
            return
        }
        guard let binding = vm.settings.screenSourceBinding,
              let image = await vm.screenSourceThumbnail(binding)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        pictures.screen = image
    }
}

struct ScenePictures {
    var screen: CGImage?
    var camera: CGImage?
}
