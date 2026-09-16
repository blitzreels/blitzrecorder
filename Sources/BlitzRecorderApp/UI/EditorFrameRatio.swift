import AppKit
import SwiftUI

struct EditorFrameRatioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isSelected ? BlitzUI.mint : .white.opacity(0.68))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    isSelected ? BlitzUI.selectedFill : BlitzUI.quietFill,
                    in: .rect(cornerRadius: 7)
                )
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

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
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
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
        scene.sceneLayout.setFrame(resized, for: request.kind)
        if request.kind == .camera {
            scene.cameraContentMode = .fill
        }
        return scene
    }
}
