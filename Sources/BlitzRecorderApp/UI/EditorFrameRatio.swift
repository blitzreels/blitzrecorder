import AppKit
import SwiftUI

enum EditorFrameRatioPreset: String, CaseIterable, Identifiable {
    case source
    case landscape
    case classic
    case square
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .landscape: return "16:9"
        case .classic: return "4:3"
        case .square: return "1:1"
        case .portrait: return "9:16"
        }
    }

    func aspectRatio(sourceRatio: CGFloat) -> CGFloat {
        switch self {
        case .source: return sourceRatio
        case .landscape: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        case .square: return 1
        case .portrait: return 9.0 / 16.0
        }
    }
}

struct EditorFrameRatioChange {
    let kind: SceneLayerKind
    let preset: EditorFrameRatioPreset
}

struct EditorFrameRatioSceneRequest {
    let kind: SceneLayerKind
    let scene: RecordingScene
}

enum EditorFrameRatioLabel {
    static func text(for ratio: CGFloat) -> String {
        let commonRatios: [(value: CGFloat, label: String)] = [
            (16.0 / 9.0, "16:9"),
            (16.0 / 10.0, "16:10"),
            (3.0 / 2.0, "3:2"),
            (4.0 / 3.0, "4:3"),
            (1, "1:1"),
            (4.0 / 5.0, "4:5"),
            (9.0 / 16.0, "9:16")
        ]
        if let match = commonRatios.first(where: { abs($0.value - ratio) < 0.02 }) {
            return match.label
        }
        return String(format: "%.2f:1", ratio)
    }
}

enum EditorFrameRatio {
    static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible())
    ]

    static func displayAspectRatio(_ request: EditorFrameRatioSceneRequest, canvasAspectRatio: CGFloat) -> CGFloat {
        let frame = request.scene.sceneLayout.frame(for: request.kind)
        guard frame.height > 0 else { return 1 }
        return frame.width / frame.height * canvasAspectRatio
    }

    static func availablePresets(sourceRatio: CGFloat) -> [EditorFrameRatioPreset] {
        EditorFrameRatioPreset.allCases.filter { preset in
            preset == .source || abs(preset.aspectRatio(sourceRatio: sourceRatio) - sourceRatio) > 0.01
        }
    }

    static func selectedPreset(_ request: EditorFrameRatioSceneRequest, canvasAspectRatio: CGFloat, sourceRatio: CGFloat) -> EditorFrameRatioPreset? {
        let currentRatio = displayAspectRatio(request, canvasAspectRatio: canvasAspectRatio)
        return availablePresets(sourceRatio: sourceRatio).first { preset in
            abs(preset.aspectRatio(sourceRatio: sourceRatio) - currentRatio) < 0.02
        }
    }

    static func applied(
        _ request: EditorFrameRatioChange,
        scene: RecordingScene,
        sourceRatio: CGFloat,
        canvasAspectRatio: CGFloat
    ) -> RecordingScene {
        var scene = scene
        let displayRatio = request.preset.aspectRatio(sourceRatio: sourceRatio)
        let normalizedRatio = displayRatio / canvasAspectRatio
        let frame = scene.sceneLayout.frame(for: request.kind)
        let resized = SceneLayerResizing.settingAspectRatio(.init(
            frame: frame,
            aspectRatio: normalizedRatio
        ))
        scene.sceneLayout.setFrame(fittedInCanvas(resized), for: request.kind)
        if request.kind.isCamera {
            scene.cameraContentMode = .fill
        }
        return scene
    }
}

/// A new shape keeps its centre but never grows past the canvas: a 4:3 camera on a 9:16 canvas used to come out
/// almost twice the canvas width.
private func fittedInCanvas(_ frame: CGRect) -> CGRect {
    let scale = min(1, 1 / max(frame.width, 0.0001), 1 / max(frame.height, 0.0001))
    let width = frame.width * scale
    let height = frame.height * scale
    let x = min(max(0, frame.midX - width / 2), 1 - width)
    let y = min(max(0, frame.midY - height / 2), 1 - height)
    return CGRect(x: x, y: y, width: width, height: height)
}

/// Shape presets for the selected layer, floating on the canvas next to the handles they affect.
struct EditorFrameRatioBar: View {
    struct Option: Identifiable {
        let title: String
        let help: String
        let isSelected: Bool
        let select: () -> Void

        var id: String { title }
    }

    struct Configuration {
        let options: [Option]
        let isLocked: Bool
        let toggleLock: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 2) {
            ForEach(configuration.options) { option in
                BlitzTab(configuration: .init(
                    title: option.title,
                    symbolName: nil,
                    isSelected: option.isSelected,
                    expands: false,
                    action: option.select
                ))
                .help(option.help)
            }
            Button(action: configuration.toggleLock) {
                Image(systemName: configuration.isLocked ? "lock.fill" : "lock.open")
                    .frame(width: 16, height: 16)
            }
            .blitzButton(.quiet)
            .accessibilityLabel(configuration.isLocked ? "Unlock shape" : "Lock shape")
            .help(configuration.isLocked
                  ? "Corner handles keep this shape. Click to reshape freely."
                  : "Handles reshape freely. Click to keep the shape.")
        }
        .controlSize(.small)
        .padding(4)
        .blitzGlass(cornerRadius: BlitzUI.cardRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frame shape")
    }
}
