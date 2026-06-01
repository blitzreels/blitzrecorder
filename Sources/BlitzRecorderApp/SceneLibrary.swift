import CoreGraphics
import Foundation

struct SceneLibrary: Codable, Equatable {
    var scenesByLayout: [CaptureLayout: [RecordingSceneDefinition]]
    var selectedSceneIDsByLayout: [CaptureLayout: UUID]

    static func defaultLibrary(currentSettings: RecordingSettings? = nil) -> SceneLibrary {
        var library = SceneLibrary(
            scenesByLayout: [
                .vertical: defaultScenes(for: .vertical),
                .horizontal: defaultScenes(for: .horizontal)
            ],
            selectedSceneIDsByLayout: [:]
        )

        for layout in CaptureLayout.allCases {
            if let firstSceneID = library.scenesByLayout[layout]?.first?.id {
                library.selectedSceneIDsByLayout[layout] = firstSceneID
            }
        }

        if let currentSettings {
            let layout = currentSettings.layout
            var scenes = library.scenesByLayout[layout] ?? []
            let currentScene = RecordingSceneDefinition(
                id: scenes.first?.id ?? UUID(),
                name: RecordingSceneDefinition.defaultName(for: currentSettings),
                layout: layout,
                snapshot: RecordingSceneSnapshot(settings: currentSettings)
            )
            if scenes.isEmpty {
                scenes.append(currentScene)
            } else {
                scenes[0] = currentScene
            }
            library.scenesByLayout[layout] = scenes
            library.selectedSceneIDsByLayout[layout] = currentScene.id
        }

        return library
    }

    mutating func ensureScenes(for layout: CaptureLayout) {
        if scenesByLayout[layout]?.isEmpty != false {
            scenesByLayout[layout] = Self.defaultScenes(for: layout)
        }
        if selectedScene(layout: layout) == nil,
           let firstSceneID = scenesByLayout[layout]?.first?.id {
            selectedSceneIDsByLayout[layout] = firstSceneID
        }
    }

    func scenes(for layout: CaptureLayout) -> [RecordingSceneDefinition] {
        scenesByLayout[layout] ?? []
    }

    func selectedScene(layout: CaptureLayout) -> RecordingSceneDefinition? {
        guard let selectedID = selectedSceneIDsByLayout[layout] else { return nil }
        return scenesByLayout[layout]?.first { $0.id == selectedID }
    }

    mutating func selectScene(id: UUID, layout: CaptureLayout) -> RecordingSceneDefinition? {
        guard let scene = scenesByLayout[layout]?.first(where: { $0.id == id }) else { return nil }
        selectedSceneIDsByLayout[layout] = id
        return scene
    }

    mutating func updateSelectedScene(layout: CaptureLayout, snapshot: RecordingSceneSnapshot) {
        ensureScenes(for: layout)
        guard let selectedID = selectedSceneIDsByLayout[layout],
              var scenes = scenesByLayout[layout],
              let index = scenes.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        scenes[index].snapshot = snapshot
        scenesByLayout[layout] = scenes
    }

    private static func defaultScenes(for layout: CaptureLayout) -> [RecordingSceneDefinition] {
        switch layout {
        case .vertical:
            return [
                makeScene(name: "Screen + Cam", layout: .vertical, preset: .screenTop50),
                makeScene(name: "Screen Only", layout: .vertical, preset: .screenFullscreen),
                makeScene(name: "Cam Only", layout: .vertical, preset: .webcamFullscreen),
                makeScene(name: "Cam Corner", layout: .vertical, preset: .cameraInset)
            ]
        case .horizontal:
            return [
                makeScene(name: "Screen + Cam", layout: .horizontal, preset: .cameraInset),
                makeScene(name: "Screen Only", layout: .horizontal, preset: .screenFullscreen),
                makeScene(name: "Cam Only", layout: .horizontal, preset: .webcamFullscreen),
                makeScene(name: "Cam Left", layout: .horizontal, preset: .webcamLeft)
            ]
        }
    }

    private static func makeScene(
        name: String,
        layout: CaptureLayout,
        preset: ScenePreset
    ) -> RecordingSceneDefinition {
        var settings = RecordingSettings()
        settings.layout = layout
        settings.selectedScenePreset = preset
        settings.sceneLayout = SceneLayout.presetLayout(preset, for: layout)
        settings.enabledSources.insert(.screen)
        settings.enabledSources.insert(.camera)
        settings.hiddenSources.remove(.screen)
        settings.hiddenSources.remove(.camera)

        if preset == .screenFullscreen {
            settings.hiddenSources.insert(.camera)
        } else if preset == .webcamFullscreen {
            settings.hiddenSources.insert(.screen)
        }

        return RecordingSceneDefinition(
            name: name,
            layout: layout,
            snapshot: RecordingSceneSnapshot(settings: settings)
        )
    }
}

struct RecordingSceneDefinition: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var layout: CaptureLayout
    var snapshot: RecordingSceneSnapshot

    init(
        id: UUID = UUID(),
        name: String,
        layout: CaptureLayout,
        snapshot: RecordingSceneSnapshot
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.snapshot = snapshot
    }

    static func defaultName(for settings: RecordingSettings) -> String {
        let visible = settings.visibleSources
        if visible.contains(.screen), visible.contains(.camera) {
            return "Screen + Cam"
        }
        if visible.contains(.screen) {
            return "Screen Only"
        }
        if visible.contains(.camera) {
            return "Cam Only"
        }
        return "Scene"
    }
}

struct RecordingSceneSnapshot: Codable, Equatable {
    var enabledVideoSources: Set<CaptureSource>
    var hiddenVideoSources: Set<CaptureSource>
    var usesPickedScreenContent: Bool
    var selectedDisplayID: String?
    var selectedCameraID: String?
    var screenCrop: CGRect?
    var cameraCropAmount: CGPoint
    var cameraCropPosition: CGPoint
    var canvasBackgroundStyle: CanvasBackgroundStyle
    var canvasPadding: CGFloat
    var sceneLayout: SceneLayout
    var selectedScenePreset: ScenePreset?

    init(settings: RecordingSettings) {
        enabledVideoSources = settings.enabledSources.intersection(Self.videoSources)
        hiddenVideoSources = settings.hiddenSources.intersection(Self.videoSources)
        usesPickedScreenContent = settings.usesPickedScreenContent
        selectedDisplayID = settings.selectedDisplayID
        selectedCameraID = settings.selectedCameraID
        screenCrop = settings.screenCrop
        cameraCropAmount = settings.cameraCropAmount
        cameraCropPosition = settings.cameraCropPosition
        canvasBackgroundStyle = settings.canvasBackgroundStyle
        canvasPadding = settings.canvasPadding
        sceneLayout = settings.sceneLayout
        selectedScenePreset = settings.selectedScenePreset
    }

    private static let videoSources: Set<CaptureSource> = [.screen, .camera]
}

enum SceneLibraryStore {
    private static let key = "scene.library.v1"

    static func load(defaults: UserDefaults? = nil, currentSettings: RecordingSettings) -> SceneLibrary {
        let defaults = defaults ?? .standard
        guard let data = defaults.data(forKey: key),
              var library = try? JSONDecoder().decode(SceneLibrary.self, from: data) else {
            return SceneLibrary.defaultLibrary(currentSettings: currentSettings)
        }
        for layout in CaptureLayout.allCases {
            library.ensureScenes(for: layout)
        }
        return library
    }

    static func save(_ library: SceneLibrary, defaults: UserDefaults? = nil) {
        let defaults = defaults ?? .standard
        if let data = try? JSONEncoder().encode(library) {
            defaults.set(data, forKey: key)
        }
    }
}

extension CaptureLayout: Codable {}
extension CaptureSource: Codable {}
extension SceneLayerKind: Codable {}
extension ScenePreset: Codable {}
extension CanvasBackgroundStyle: Codable {}

extension SceneLayout: Codable {
    private enum CodingKeys: String, CodingKey {
        case screenFrame
        case cameraFrame
        case layerOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            screenFrame: try container.decode(CGRect.self, forKey: .screenFrame),
            cameraFrame: try container.decode(CGRect.self, forKey: .cameraFrame),
            layerOrder: try container.decode([SceneLayerKind].self, forKey: .layerOrder)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(screenFrame, forKey: .screenFrame)
        try container.encode(cameraFrame, forKey: .cameraFrame)
        try container.encode(layerOrder, forKey: .layerOrder)
    }
}
