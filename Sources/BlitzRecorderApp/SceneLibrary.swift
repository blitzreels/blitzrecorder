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

    func layout(ofSceneID id: UUID) -> CaptureLayout? {
        for layout in CaptureLayout.allCases where scenesByLayout[layout]?.contains(where: { $0.id == id }) == true {
            return layout
        }
        return nil
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

    @discardableResult
    mutating func createScene(
        layout: CaptureLayout,
        name: String,
        snapshot: RecordingSceneSnapshot
    ) -> RecordingSceneDefinition {
        ensureScenes(for: layout)
        let scene = RecordingSceneDefinition(
            name: uniqueSceneName(name, layout: layout),
            layout: layout,
            snapshot: snapshot
        )
        scenesByLayout[layout, default: []].append(scene)
        selectedSceneIDsByLayout[layout] = scene.id
        return scene
    }

    @discardableResult
    mutating func duplicateScene(id: UUID, layout: CaptureLayout) -> RecordingSceneDefinition? {
        ensureScenes(for: layout)
        guard var scenes = scenesByLayout[layout],
              let index = scenes.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let original = scenes[index]
        let duplicate = RecordingSceneDefinition(
            name: uniqueSceneName("\(original.name) Copy", layout: layout),
            layout: layout,
            snapshot: original.snapshot
        )
        scenes.insert(duplicate, at: min(index + 1, scenes.count))
        scenesByLayout[layout] = scenes
        selectedSceneIDsByLayout[layout] = duplicate.id
        return duplicate
    }

    @discardableResult
    mutating func renameScene(id: UUID, layout: CaptureLayout, name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              var scenes = scenesByLayout[layout],
              let index = scenes.firstIndex(where: { $0.id == id }) else {
            return false
        }
        scenes[index].name = uniqueSceneName(trimmedName, layout: layout, ignoring: id)
        scenesByLayout[layout] = scenes
        return true
    }

    @discardableResult
    mutating func deleteScene(id: UUID, layout: CaptureLayout) -> Bool {
        ensureScenes(for: layout)
        guard var scenes = scenesByLayout[layout],
              scenes.count > 1,
              let index = scenes.firstIndex(where: { $0.id == id }) else {
            return false
        }
        scenes.remove(at: index)
        scenesByLayout[layout] = scenes
        if selectedSceneIDsByLayout[layout] == id {
            let nextIndex = min(index, scenes.count - 1)
            selectedSceneIDsByLayout[layout] = scenes[nextIndex].id
        }
        return true
    }

    @discardableResult
    mutating func moveScene(id: UUID, layout: CaptureLayout, to targetIndex: Int) -> Bool {
        ensureScenes(for: layout)
        guard var scenes = scenesByLayout[layout],
              let sourceIndex = scenes.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let scene = scenes.remove(at: sourceIndex)
        let clampedIndex = min(max(targetIndex, 0), scenes.count)
        scenes.insert(scene, at: clampedIndex)
        scenesByLayout[layout] = scenes
        return true
    }

    @discardableResult
    mutating func resetScene(id: UUID, layout: CaptureLayout, snapshot: RecordingSceneSnapshot) -> Bool {
        ensureScenes(for: layout)
        guard var scenes = scenesByLayout[layout],
              let index = scenes.firstIndex(where: { $0.id == id }) else {
            return false
        }
        scenes[index].snapshot = snapshot
        scenesByLayout[layout] = scenes
        return true
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

    private func uniqueSceneName(_ requestedName: String, layout: CaptureLayout, ignoring ignoredID: UUID? = nil) -> String {
        let fallbackName = "Scene"
        let baseName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseName = baseName.isEmpty ? fallbackName : baseName
        let existingNames = Set((scenesByLayout[layout] ?? [])
            .filter { $0.id != ignoredID }
            .map(\.name))
        guard existingNames.contains(normalizedBaseName) else {
            return normalizedBaseName
        }

        var index = 2
        while existingNames.contains("\(normalizedBaseName) \(index)") {
            index += 1
        }
        return "\(normalizedBaseName) \(index)"
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
    var screenSourceBinding: ScreenSourceBinding?
    var selectedDisplayID: String?
    var selectedCameraID: String?
    var screenCrop: CGRect?
    var cameraCropAmount: CGPoint
    var cameraCropPosition: CGPoint
    var canvasBackgroundStyle: CanvasBackgroundStyle
    var canvasBackgroundAnimated: Bool
    var canvasPadding: CGFloat
    var cameraContentMode: CameraContentMode
    var cameraFramePadding: CGFloat
    var cameraShadowEnabled: Bool
    var sceneLayout: SceneLayout
    var selectedScenePreset: ScenePreset?

    init(settings: RecordingSettings) {
        enabledVideoSources = settings.enabledSources.intersection(Self.videoSources)
        hiddenVideoSources = settings.hiddenSources.intersection(Self.videoSources)
        usesPickedScreenContent = settings.usesPickedScreenContent
        screenSourceBinding = settings.screenSourceBinding
        selectedDisplayID = settings.selectedDisplayID
        selectedCameraID = settings.selectedCameraID
        screenCrop = settings.screenCrop
        cameraCropAmount = settings.cameraCropAmount
        cameraCropPosition = settings.cameraCropPosition
        canvasBackgroundStyle = settings.canvasBackgroundStyle
        canvasBackgroundAnimated = settings.canvasBackgroundAnimated
        canvasPadding = settings.canvasPadding
        cameraContentMode = settings.cameraContentMode
        cameraFramePadding = 0
        cameraShadowEnabled = settings.cameraShadowEnabled
        sceneLayout = settings.sceneLayout
        selectedScenePreset = settings.selectedScenePreset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledVideoSources = try container.decode(Set<CaptureSource>.self, forKey: .enabledVideoSources)
        hiddenVideoSources = try container.decode(Set<CaptureSource>.self, forKey: .hiddenVideoSources)
        usesPickedScreenContent = try container.decode(Bool.self, forKey: .usesPickedScreenContent)
        selectedDisplayID = try container.decodeIfPresent(String.self, forKey: .selectedDisplayID)
        screenSourceBinding = try container.decodeIfPresent(ScreenSourceBinding.self, forKey: .screenSourceBinding)
            ?? .display(id: selectedDisplayID)
        selectedCameraID = try container.decodeIfPresent(String.self, forKey: .selectedCameraID)
        screenCrop = try container.decodeIfPresent(CGRect.self, forKey: .screenCrop)
        cameraCropAmount = try container.decode(CGPoint.self, forKey: .cameraCropAmount)
        cameraCropPosition = try container.decode(CGPoint.self, forKey: .cameraCropPosition)
        canvasBackgroundStyle = try container.decode(CanvasBackgroundStyle.self, forKey: .canvasBackgroundStyle)
        canvasBackgroundAnimated = try container.decodeIfPresent(Bool.self, forKey: .canvasBackgroundAnimated) ?? false
        canvasPadding = try container.decode(CGFloat.self, forKey: .canvasPadding)
        cameraContentMode = try container.decodeIfPresent(CameraContentMode.self, forKey: .cameraContentMode) ?? .fill
        _ = try container.decodeIfPresent(CGFloat.self, forKey: .cameraFramePadding)
        cameraFramePadding = 0
        cameraShadowEnabled = try container.decodeIfPresent(Bool.self, forKey: .cameraShadowEnabled) ?? false
        sceneLayout = try container.decode(SceneLayout.self, forKey: .sceneLayout)
        selectedScenePreset = try container.decodeIfPresent(ScenePreset.self, forKey: .selectedScenePreset)
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
