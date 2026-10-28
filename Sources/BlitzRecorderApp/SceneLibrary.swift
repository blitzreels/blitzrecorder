import CoreGraphics
import Foundation

struct SceneLibrary: Codable, Equatable {
    var scenesByLayout: [CaptureLayout: [RecordingSceneDefinition]]
    var selectedSceneIDsByLayout: [CaptureLayout: UUID]

    static func defaultLibrary(currentSettings: RecordingSettings? = nil) -> SceneLibrary {
        var library = SceneLibrary(scenesByLayout: [:], selectedSceneIDsByLayout: [:])
        library.canonicalize(cameraAngleCount: currentSettings?.extraCameraAngleIDs.count ?? 0)
        guard let currentSettings,
              var scenes = library.scenesByLayout[currentSettings.layout],
              !scenes.isEmpty else { return library }
        let index = scenes.firstIndex { $0.snapshot.selectedScenePreset == currentSettings.selectedScenePreset } ?? 0
        var snapshot = RecordingSceneSnapshot(settings: currentSettings)
        snapshot.enabledVideoSources = scenes[index].snapshot.enabledVideoSources
        snapshot.hiddenVideoSources = scenes[index].snapshot.hiddenVideoSources
        snapshot.selectedScenePreset = scenes[index].snapshot.selectedScenePreset
        scenes[index].snapshot = snapshot
        library.scenesByLayout[currentSettings.layout] = scenes
        library.selectedSceneIDsByLayout[currentSettings.layout] = scenes[index].id
        return library
    }

    static func presets(for layout: CaptureLayout) -> [ScenePreset] {
        switch layout {
        case .vertical:
            return [.screenTop50, .cameraInset, .screenFullscreen, .webcamFullscreen]
        case .horizontal, .square:
            return [.webcamLeft, .cameraInset, .screenFullscreen, .webcamFullscreen]
        }
    }

    /// One scene of the strip: a layout preset and the camera that fills its camera slot.
    struct SceneSpec: Equatable {
        let preset: ScenePreset
        let cameraFeeds: CameraFeeds
    }

    /// The base scenes, then for each added camera angle its full-frame scene and its scene with the screen,
    /// then the two-camera layouts with Camera 1 and Camera 2.
    static func sceneSpecs(for layout: CaptureLayout, cameraAngleCount: Int) -> [SceneSpec] {
        let base = presets(for: layout).map { SceneSpec(preset: $0, cameraFeeds: .main) }
        let twoCameras = cameraAngleCount > 0
            ? ScenePreset.twoCameraPresets.map { SceneSpec(preset: $0, cameraFeeds: .main) }
            : []
        let angles = (0..<cameraAngleCount).flatMap { index -> [SceneSpec] in
            let feeds = CameraFeeds(
                camera: NumberedSourceTracks.cameraAngles.role(number: index + NumberedSourceTracks.cameraAngles.firstNumber),
                secondCamera: CameraFeeds.firstAngleRole
            )
            return [
                SceneSpec(preset: .webcamFullscreen, cameraFeeds: feeds),
                SceneSpec(preset: layout == .vertical ? .screenTop50 : .webcamLeft, cameraFeeds: feeds)
            ]
        }
        return base + angles + twoCameras
    }

    /// Scene names number the cameras only once a second camera exists, so one-camera setups keep "Camera".
    static func name(for spec: SceneSpec, numbersCameras: Bool) -> String {
        guard numbersCameras, let number = CameraFeeds.angleNumber(role: spec.cameraFeeds.camera) else {
            return name(for: spec.preset)
        }
        switch spec.preset {
        case .twoCameras: return "Two Cameras"
        case .twoCamerasScreen: return "Screen + Two Cameras"
        case .webcamFullscreen: return "Camera \(number)"
        case .webcamLeft, .cameraRight, .screenTop50: return "Screen + Camera \(number)"
        case .cameraInset: return "Camera \(number) Inset"
        default: return name(for: spec.preset)
        }
    }

    static func name(for preset: ScenePreset) -> String {
        switch preset {
        case .webcamLeft, .cameraRight: return "Screen + Camera"
        case .cameraInset: return "Camera Inset"
        case .screenTop50: return "Screen + Camera"
        case .screenFullscreen: return "Screen"
        case .webcamFullscreen: return "Camera"
        default: return preset.rawValue
        }
    }

    /// Rebuilds every layout's scenes from `sceneSpecs`, keeping the IDs and edits of scenes that still exist.
    /// Scenes of a removed camera angle go away; if one was selected, the first scene is selected instead.
    @discardableResult
    mutating func canonicalize(cameraAngleCount: Int) -> Bool {
        let original = self
        for layout in CaptureLayout.allCases {
            let existing = scenes(for: layout).map(Self.migratingCameraRight)
            let selectedSpec = selectedScene(layout: layout).map(Self.migratingCameraRight).flatMap(Self.spec(of:))
            let scenes = Self.sceneSpecs(for: layout, cameraAngleCount: cameraAngleCount).map { spec in
                let fresh = Self.makeScene(.init(layout: layout, spec: spec, numbersCameras: cameraAngleCount > 0))
                let matches = existing.filter {
                    $0.snapshot.selectedScenePreset == spec.preset && $0.snapshot.cameraFeeds == spec.cameraFeeds
                }
                let selectedMatch = matches.first { $0.id == selectedSceneIDsByLayout[layout] }
                guard let match = selectedMatch ?? matches.first else {
                    return fresh
                }
                var snapshot = match.snapshot
                snapshot.enabledVideoSources = fresh.snapshot.enabledVideoSources
                snapshot.hiddenVideoSources = fresh.snapshot.hiddenVideoSources
                snapshot.sceneLayout = Self.migratingLegacySideBySideWidth(snapshot.sceneLayout, layout: layout)
                return RecordingSceneDefinition(
                    id: match.id,
                    name: fresh.name,
                    layout: layout,
                    snapshot: snapshot
                )
            }
            scenesByLayout[layout] = scenes
            selectedSceneIDsByLayout[layout] = (scenes.first { $0.id == selectedSceneIDsByLayout[layout] }
                ?? scenes.first { Self.spec(of: $0) == selectedSpec }
                ?? scenes.first)?.id
        }
        return self != original
    }

    private static func spec(of scene: RecordingSceneDefinition) -> SceneSpec? {
        scene.snapshot.selectedScenePreset.map { SceneSpec(preset: $0, cameraFeeds: scene.snapshot.cameraFeeds) }
    }

    private static func migratingLegacySideBySideWidth(_ sceneLayout: SceneLayout, layout: CaptureLayout) -> SceneLayout {
        guard layout != .vertical,
              let side = sceneLayout.cameraSide,
              let width = sceneLayout.sideBySideCameraWidth,
              [1.0 / 3.0, 0.4].contains(where: { abs($0 - width) < 0.002 }) else { return sceneLayout }
        return SceneLayout.sideBySideLayout(.init(
            cameraWidth: SceneLayout.defaultSideBySideCameraWidth(for: layout),
            cameraSide: side
        ))
    }

    private static func migratingCameraRight(_ scene: RecordingSceneDefinition) -> RecordingSceneDefinition {
        guard scene.snapshot.selectedScenePreset == .cameraRight else { return scene }
        var scene = scene
        scene.snapshot.selectedScenePreset = .webcamLeft
        return scene
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
        guard let selectedID = selectedSceneIDsByLayout[layout],
              var scenes = scenesByLayout[layout],
              let index = scenes.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        var snapshot = snapshot
        snapshot.enabledVideoSources = scenes[index].snapshot.enabledVideoSources
        snapshot.hiddenVideoSources = scenes[index].snapshot.hiddenVideoSources
        snapshot.selectedScenePreset = scenes[index].snapshot.selectedScenePreset
        snapshot.cameraFeeds = scenes[index].snapshot.cameraFeeds
        scenes[index].snapshot = snapshot
        scenesByLayout[layout] = scenes
    }

    private struct DefaultSceneRequest {
        let layout: CaptureLayout
        let spec: SceneSpec
        let numbersCameras: Bool
    }

    private static func makeScene(_ request: DefaultSceneRequest) -> RecordingSceneDefinition {
        let preset = request.spec.preset
        var settings = RecordingSettings()
        settings.layout = request.layout
        settings.selectedScenePreset = preset
        settings.cameraFeeds = request.spec.cameraFeeds
        settings.sceneLayout = SceneLayout.presetLayout(preset, for: request.layout)
        settings.enabledSources.formUnion([.screen, .camera])
        settings.hiddenSources.subtract([.screen, .camera])
        settings.hiddenSources.formUnion(Set<CaptureSource>([.screen, .camera]).subtracting(preset.requiredVideoSources))

        return RecordingSceneDefinition(
            name: name(for: request.spec, numbersCameras: request.numbersCameras),
            layout: request.layout,
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
}

struct RecordingSceneSnapshot: Codable, Equatable {
    var enabledVideoSources: Set<CaptureSource>
    var hiddenVideoSources: Set<CaptureSource>
    var usesPickedScreenContent: Bool
    var pickedScreenContentSelectionID: UUID?
    var screenSourceBinding: ScreenSourceBinding?
    var selectedDisplayID: String?
    var selectedCameraID: String?
    var screenCrop: CGRect?
    var screenSourceAspectRatio: CGFloat?
    var cameraCropAmount: CGPoint
    var cameraCropPosition: CGPoint
    var secondCameraCropAmount: CGPoint
    var secondCameraCropPosition: CGPoint
    var canvasBackgroundStyle: CanvasBackgroundStyle
    var canvasBackgroundAnimated: Bool
    var canvasPadding: CGFloat
    var screenCornerRadius: CGFloat
    var screenShadowEnabled: Bool
    var screenWindowZoom: CGFloat
    var screenContentMode: CameraContentMode
    var cameraContentMode: CameraContentMode
    var cameraFramePadding: CGFloat
    var cameraShadowEnabled: Bool
    var sceneLayout: SceneLayout
    var cameraFeeds: CameraFeeds
    var selectedScenePreset: ScenePreset?

    init(settings: RecordingSettings) {
        enabledVideoSources = settings.enabledSources.intersection(Self.videoSources)
        hiddenVideoSources = settings.hiddenSources.intersection(Self.videoSources)
        usesPickedScreenContent = settings.usesPickedScreenContent
        pickedScreenContentSelectionID = nil
        screenSourceBinding = settings.screenSourceBinding
        selectedDisplayID = settings.selectedDisplayID
        selectedCameraID = settings.selectedCameraID
        screenCrop = settings.screenCrop
        screenSourceAspectRatio = settings.screenSourceAspectRatio
        cameraCropAmount = settings.cameraCropAmount
        cameraCropPosition = settings.cameraCropPosition
        secondCameraCropAmount = settings.secondCameraCropAmount
        secondCameraCropPosition = settings.secondCameraCropPosition
        canvasBackgroundStyle = settings.canvasBackgroundStyle
        canvasBackgroundAnimated = settings.canvasBackgroundAnimated
        canvasPadding = settings.canvasPadding
        screenCornerRadius = settings.screenCornerRadius
        screenShadowEnabled = settings.screenShadowEnabled
        screenWindowZoom = settings.screenWindowZoom
        screenContentMode = settings.screenContentMode
        cameraContentMode = settings.cameraContentMode
        cameraFramePadding = 0
        cameraShadowEnabled = settings.cameraShadowEnabled
        sceneLayout = settings.sceneLayout
        cameraFeeds = settings.cameraFeeds
        selectedScenePreset = settings.selectedScenePreset
    }

    var restoresConcreteScreenSource: Bool {
        screenSourceBinding?.isConcreteSelection == true || usesPickedScreenContent
    }

    func applying(to settings: RecordingSettings) -> RecordingSettings {
        var settings = settings
        settings.hiddenSources = settings.hiddenSources
            .subtracting(Self.videoSources)
            .union(hiddenVideoSources)
        settings.sceneLayout = sceneLayout
        settings.cameraFeeds = cameraFeeds
        settings.selectedScenePreset = selectedScenePreset
        settings.screenWindowZoom = screenWindowZoom
        settings.screenContentMode = screenContentMode
        settings.cameraCropAmount = cameraCropAmount
        settings.cameraCropPosition = cameraCropPosition
        settings.secondCameraCropAmount = secondCameraCropAmount
        settings.secondCameraCropPosition = secondCameraCropPosition
        return settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledVideoSources = try container.decode(Set<CaptureSource>.self, forKey: .enabledVideoSources)
        hiddenVideoSources = try container.decode(Set<CaptureSource>.self, forKey: .hiddenVideoSources)
        usesPickedScreenContent = try container.decode(Bool.self, forKey: .usesPickedScreenContent)
        pickedScreenContentSelectionID = try container.decodeIfPresent(
            UUID.self,
            forKey: .pickedScreenContentSelectionID
        )
        selectedDisplayID = try container.decodeIfPresent(String.self, forKey: .selectedDisplayID)
        screenSourceBinding = try container.decodeIfPresent(ScreenSourceBinding.self, forKey: .screenSourceBinding)
            ?? .display(id: selectedDisplayID)
        selectedCameraID = try container.decodeIfPresent(String.self, forKey: .selectedCameraID)
        screenCrop = try container.decodeIfPresent(CGRect.self, forKey: .screenCrop)
        screenSourceAspectRatio = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .screenSourceAspectRatio
        )
        cameraCropAmount = try container.decode(CGPoint.self, forKey: .cameraCropAmount)
        cameraCropPosition = try container.decode(CGPoint.self, forKey: .cameraCropPosition)
        secondCameraCropAmount = try container.decodeIfPresent(CGPoint.self, forKey: .secondCameraCropAmount) ?? .zero
        secondCameraCropPosition = try container.decodeIfPresent(CGPoint.self, forKey: .secondCameraCropPosition) ?? .zero
        canvasBackgroundStyle = try container.decode(CanvasBackgroundStyle.self, forKey: .canvasBackgroundStyle)
        canvasBackgroundAnimated = try container.decodeIfPresent(Bool.self, forKey: .canvasBackgroundAnimated) ?? false
        canvasPadding = try container.decode(CGFloat.self, forKey: .canvasPadding)
        screenCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .screenCornerRadius) ?? 0
        screenShadowEnabled = try container.decodeIfPresent(Bool.self, forKey: .screenShadowEnabled) ?? false
        screenWindowZoom = ScreenSourceZoomGeometry.clamped(
            try container.decodeIfPresent(CGFloat.self, forKey: .screenWindowZoom) ?? 1
        )
        screenContentMode = try container.decodeIfPresent(CameraContentMode.self, forKey: .screenContentMode) ?? .fill
        cameraContentMode = try container.decodeIfPresent(CameraContentMode.self, forKey: .cameraContentMode) ?? .fill
        _ = try container.decodeIfPresent(CGFloat.self, forKey: .cameraFramePadding)
        cameraFramePadding = 0
        cameraShadowEnabled = try container.decodeIfPresent(Bool.self, forKey: .cameraShadowEnabled) ?? false
        sceneLayout = try container.decode(SceneLayout.self, forKey: .sceneLayout)
        cameraFeeds = try container.decodeIfPresent(CameraFeeds.self, forKey: .cameraFeeds) ?? .main
        selectedScenePreset = try container.decodeIfPresent(ScenePreset.self, forKey: .scenePresetV2)
            ?? container.decodeIfPresent(ScenePreset.self, forKey: .selectedScenePreset)
    }

    private enum CodingKeys: String, CodingKey {
        case enabledVideoSources, hiddenVideoSources, usesPickedScreenContent, pickedScreenContentSelectionID
        case screenSourceBinding, selectedDisplayID, selectedCameraID, screenCrop, screenSourceAspectRatio
        case cameraCropAmount, cameraCropPosition, canvasBackgroundStyle, canvasBackgroundAnimated, canvasPadding
        case screenCornerRadius, screenShadowEnabled, screenWindowZoom, screenContentMode, cameraContentMode
        case cameraFramePadding, cameraShadowEnabled, sceneLayout, cameraFeeds, selectedScenePreset
        case secondCameraCropAmount, secondCameraCropPosition
        /// Holds presets older builds cannot decode, so they skip that scene instead of dropping the library.
        case scenePresetV2
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledVideoSources, forKey: .enabledVideoSources)
        try container.encode(hiddenVideoSources, forKey: .hiddenVideoSources)
        try container.encode(usesPickedScreenContent, forKey: .usesPickedScreenContent)
        try container.encodeIfPresent(pickedScreenContentSelectionID, forKey: .pickedScreenContentSelectionID)
        try container.encodeIfPresent(screenSourceBinding, forKey: .screenSourceBinding)
        try container.encodeIfPresent(selectedDisplayID, forKey: .selectedDisplayID)
        try container.encodeIfPresent(selectedCameraID, forKey: .selectedCameraID)
        try container.encodeIfPresent(screenCrop, forKey: .screenCrop)
        try container.encodeIfPresent(screenSourceAspectRatio, forKey: .screenSourceAspectRatio)
        try container.encode(cameraCropAmount, forKey: .cameraCropAmount)
        try container.encode(cameraCropPosition, forKey: .cameraCropPosition)
        if secondCameraCropAmount != .zero || secondCameraCropPosition != .zero {
            try container.encode(secondCameraCropAmount, forKey: .secondCameraCropAmount)
            try container.encode(secondCameraCropPosition, forKey: .secondCameraCropPosition)
        }
        try container.encode(canvasBackgroundStyle, forKey: .canvasBackgroundStyle)
        try container.encode(canvasBackgroundAnimated, forKey: .canvasBackgroundAnimated)
        try container.encode(canvasPadding, forKey: .canvasPadding)
        try container.encode(screenCornerRadius, forKey: .screenCornerRadius)
        try container.encode(screenShadowEnabled, forKey: .screenShadowEnabled)
        try container.encode(screenWindowZoom, forKey: .screenWindowZoom)
        try container.encode(screenContentMode, forKey: .screenContentMode)
        try container.encode(cameraContentMode, forKey: .cameraContentMode)
        try container.encode(cameraFramePadding, forKey: .cameraFramePadding)
        try container.encode(cameraShadowEnabled, forKey: .cameraShadowEnabled)
        try container.encode(sceneLayout, forKey: .sceneLayout)
        try container.encode(cameraFeeds, forKey: .cameraFeeds)
        let presetKey: CodingKeys = selectedScenePreset?.needsSecondCamera == true ? .scenePresetV2 : .selectedScenePreset
        try container.encodeIfPresent(selectedScenePreset, forKey: presetKey)
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
        if library.canonicalize(cameraAngleCount: currentSettings.extraCameraAngleIDs.count) {
            save(library, defaults: defaults)
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
        case cameraMask
        case secondCameraFrame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            screenFrame: try container.decode(CGRect.self, forKey: .screenFrame),
            cameraFrame: try container.decode(CGRect.self, forKey: .cameraFrame),
            layerOrder: try container.decode([SceneLayerKind].self, forKey: .layerOrder),
            cameraMask: try container.decodeIfPresent(SceneCameraMask.self, forKey: .cameraMask) ?? .rectangle,
            secondCameraFrame: try container.decodeIfPresent(CGRect.self, forKey: .secondCameraFrame)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(screenFrame, forKey: .screenFrame)
        try container.encode(cameraFrame, forKey: .cameraFrame)
        try container.encode(layerOrder.filter(SceneLayerKind.persistedOrderKinds.contains), forKey: .layerOrder)
        try container.encode(cameraMask, forKey: .cameraMask)
        try container.encodeIfPresent(secondCameraFrame, forKey: .secondCameraFrame)
    }
}
