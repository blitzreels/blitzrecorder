import SwiftUI

extension SceneTileShape {
    func title(cameraAspectRatio: CGFloat) -> String {
        switch self {
        case .source: EditorFrameRatioLabel.text(for: cameraAspectRatio)
        case .ratio(let ratio): EditorFrameRatioLabel.text(for: ratio)
        case .fill: "Fill"
        }
    }

    func help(includesScreen: Bool) -> String {
        let screen = includesScreen ? " The screen takes the room the cameras give up." : ""
        switch self {
        case .source: return "Each camera keeps its whole picture"
        case .ratio: return "Trims the sides of each camera so the tiles get taller." + screen
        case .fill: return "Each tile takes all its space; the picture is trimmed to fit"
        }
    }
}

/// Spacing and shape of the two camera tiles. Both tiles always change together, so they stay even.
struct SceneTileControls: View {
    struct Configuration {
        /// Nil once a tile was moved or resized by hand: picking any option lines the tiles up again.
        let tiles: SceneTiles?
        let layout: CaptureLayout
        let cameraAspectRatio: CGFloat
        let includesScreen: Bool
        let apply: (SceneTiles) -> Void
    }

    let configuration: Configuration

    private var base: SceneTiles { configuration.tiles ?? .defaults(for: configuration.layout) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                BlitzUI.sectionLabel("Spacing")
                BlitzSegmentedPicker(configuration: .init(
                    title: "Space around the cameras",
                    options: SceneTileSpacing.allCases.map(Optional.some),
                    selection: Binding(get: { configuration.tiles?.spacing }, set: { spacing in
                        guard let spacing else { return }
                        configuration.apply(.init(spacing: spacing, shape: base.shape))
                    }),
                    label: { $0?.title ?? "" },
                    help: { $0 == SceneTileSpacing.none ? "Tiles touch the edges and each other"
                                                        : "Space around and between the tiles shows the background" }
                ))
                .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 6) {
                BlitzUI.sectionLabel("Shape")
                BlitzSegmentedPicker(configuration: .init(
                    title: "Camera shape",
                    options: SceneTileShape.options(cameraAspectRatio: configuration.cameraAspectRatio).map(Optional.some),
                    selection: Binding(get: { configuration.tiles?.shape }, set: { shape in
                        guard let shape else { return }
                        configuration.apply(.init(spacing: base.spacing, shape: shape))
                    }),
                    label: { $0?.title(cameraAspectRatio: configuration.cameraAspectRatio) ?? "" },
                    help: { $0?.help(includesScreen: configuration.includesScreen) }
                ))
                .controlSize(.small)
            }
            if configuration.tiles == nil {
                Text("A camera was moved by hand. Pick a spacing or shape to line both up again.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("Camera tiles") {
    @Previewable @State var tiles: SceneTiles? = .defaults(for: .horizontal)
    SceneTileControls(configuration: .init(
        tiles: tiles,
        layout: .horizontal,
        cameraAspectRatio: 16.0 / 9.0,
        includesScreen: true,
        apply: { tiles = $0 }
    ))
    .padding(14)
    .frame(width: 280)
}

