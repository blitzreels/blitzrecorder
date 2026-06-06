import BlitzRecorderCore
import CoreGraphics
import Foundation

enum RecordingSettingsStore {
    private enum Key {
        static let layout = "recording.layout"
        static let outputResolution = "recording.outputResolution"
        static let outputVideoFormat = "recording.outputVideoFormat"
        static let framesPerSecond = "recording.framesPerSecond"
        static let customVideoBitrate = "recording.customVideoBitrate"
        static let audioQuality = "recording.audioQuality"
        static let sourceAudioFormat = "recording.sourceAudioFormat"
        static let microphoneGain = "recording.microphoneGain"
        static let systemAudioGain = "recording.systemAudioGain"
        static let removesCameraBackgroundAfterRecording = "recording.removesCameraBackgroundAfterRecording"
        static let savesSourceFiles = "recording.savesSourceFiles"
        static let renamesRecordingsFromSpeech = "recording.renamesRecordingsFromSpeech"
        static let showsRuleOfThirdsOverlay = "recording.showsRuleOfThirdsOverlay"
        static let socialSafeZoneOverlay = "recording.socialSafeZoneOverlay"
        static let includeCursor = "recording.includeCursor"
        static let enabledSources = "recording.enabledSources"
        static let hiddenSources = "recording.hiddenSources"
        static let screenSourceBinding = "recording.screenSourceBinding"
        static let selectedDisplayID = "recording.selectedDisplayID"
        static let selectedCameraID = "recording.selectedCameraID"
        static let selectedMicrophoneID = "recording.selectedMicrophoneID"
        static let trustedRemoteCameraServiceIDs = "recording.trustedRemoteCameraServiceIDs"
        static let remoteCameraSettingsByServiceID = "recording.remoteCameraSettingsByServiceID"
        static let outputDirectoryPath = "recording.outputDirectoryPath"
        static let outputDirectoryBookmark = "recording.outputDirectoryBookmark"
        static let screenCrop = "screen.crop"
        static let cameraCropAmount = "camera.cropAmount"
        static let cameraCropPosition = "camera.cropPosition"
        static let canvasBackgroundStyle = "scene.canvasBackgroundStyle"
        static let canvasBackgroundAnimated = "scene.canvasBackgroundAnimated"
        static let canvasPadding = "scene.canvasPadding"
        static let screenFrame = "scene.screenFrame"
        static let cameraFrame = "scene.cameraFrame"
        static let layerOrder = "scene.layerOrder"
        static let selectedScenePreset = "scene.selectedScenePreset"
    }

    static func load(defaults: UserDefaults? = nil) -> RecordingSettings {
        let defaults = defaults ?? defaultStore()
        var settings = RecordingSettings()

        if let rawLayout = defaults.string(forKey: Key.layout),
           let layout = CaptureLayout(rawValue: rawLayout) {
            settings.layout = layout
        }

        if let rawResolution = defaults.string(forKey: Key.outputResolution),
           let outputResolution = OutputResolution(rawValue: rawResolution) {
            settings.outputResolution = outputResolution
        }

        if let rawFormat = defaults.string(forKey: Key.outputVideoFormat),
           let outputVideoFormat = OutputVideoFormat(rawValue: rawFormat) {
            settings.outputVideoFormat = outputVideoFormat
        }

        let framesPerSecond = defaults.integer(forKey: Key.framesPerSecond)
        if RecordingSettings.supportedFrameRates.contains(framesPerSecond) {
            settings.framesPerSecond = framesPerSecond
        }

        if defaults.object(forKey: Key.customVideoBitrate) != nil {
            let stored = defaults.integer(forKey: Key.customVideoBitrate)
            if stored > 0 {
                settings.customVideoBitrate = min(
                    RecordingSettings.maxCustomVideoBitrate,
                    max(RecordingSettings.minCustomVideoBitrate, stored)
                )
            }
        }

        if let rawAudioQuality = defaults.string(forKey: Key.audioQuality),
           let audioQuality = AudioQuality(rawValue: rawAudioQuality) {
            settings.audioQuality = audioQuality
        }

        if let rawSourceAudioFormat = defaults.string(forKey: Key.sourceAudioFormat),
           let sourceAudioFormat = SourceAudioFormat(rawValue: rawSourceAudioFormat) {
            settings.sourceAudioFormat = sourceAudioFormat
        }

        if defaults.object(forKey: Key.microphoneGain) != nil {
            settings.microphoneGain = clampedGain(defaults.double(forKey: Key.microphoneGain))
        }

        if defaults.object(forKey: Key.systemAudioGain) != nil {
            settings.systemAudioGain = clampedGain(defaults.double(forKey: Key.systemAudioGain))
        }

        if defaults.object(forKey: Key.removesCameraBackgroundAfterRecording) != nil {
            settings.removesCameraBackgroundAfterRecording = defaults.bool(forKey: Key.removesCameraBackgroundAfterRecording)
        }

        if defaults.object(forKey: Key.savesSourceFiles) != nil {
            settings.savesSourceFiles = defaults.bool(forKey: Key.savesSourceFiles)
        }

        if defaults.object(forKey: Key.renamesRecordingsFromSpeech) != nil {
            settings.renamesRecordingsFromSpeech = defaults.bool(forKey: Key.renamesRecordingsFromSpeech)
        }

        if defaults.object(forKey: Key.showsRuleOfThirdsOverlay) != nil {
            settings.showsRuleOfThirdsOverlay = defaults.bool(forKey: Key.showsRuleOfThirdsOverlay)
        }

        if let rawSocialSafeZoneOverlay = defaults.string(forKey: Key.socialSafeZoneOverlay),
           let socialSafeZoneOverlay = SocialVideoSafeZone(rawValue: rawSocialSafeZoneOverlay) {
            settings.socialSafeZoneOverlay = socialSafeZoneOverlay
        }

        if defaults.object(forKey: Key.includeCursor) != nil {
            settings.includeCursor = defaults.bool(forKey: Key.includeCursor)
        }

        if let rawSources = defaults.stringArray(forKey: Key.enabledSources) {
            let sources = Set(rawSources.compactMap(CaptureSource.init(rawValue:)))
            if !sources.isEmpty {
                settings.enabledSources = sources
            }
        }
        if let rawSources = defaults.stringArray(forKey: Key.hiddenSources) {
            settings.hiddenSources = Set(rawSources.compactMap(CaptureSource.init(rawValue:)))
        }

        settings.selectedDisplayID = defaults.string(forKey: Key.selectedDisplayID)
        if let data = defaults.data(forKey: Key.screenSourceBinding),
           let binding = try? JSONDecoder().decode(ScreenSourceBinding.self, from: data) {
            settings.screenSourceBinding = binding
        } else if let selectedDisplayID = settings.selectedDisplayID {
            settings.screenSourceBinding = .display(id: selectedDisplayID)
        }
        settings.selectedCameraID = defaults.string(forKey: Key.selectedCameraID)
        settings.selectedMicrophoneID = defaults.string(forKey: Key.selectedMicrophoneID)
        settings.trustedRemoteCameraServiceIDs = Set(defaults.stringArray(forKey: Key.trustedRemoteCameraServiceIDs) ?? [])
        settings.remoteCameraSettingsByServiceID = remoteCameraSettingsByServiceID(defaults: defaults)
        settings.screenCrop = rect(for: Key.screenCrop, defaults: defaults)
        settings.cameraCropAmount = point(for: Key.cameraCropAmount, defaults: defaults) ?? .zero
        settings.cameraCropPosition = point(for: Key.cameraCropPosition, defaults: defaults) ?? .zero
        if let rawCanvasBackgroundStyle = defaults.string(forKey: Key.canvasBackgroundStyle),
           let canvasBackgroundStyle = CanvasBackgroundStyle(rawValue: rawCanvasBackgroundStyle) {
            settings.canvasBackgroundStyle = canvasBackgroundStyle
        }
        if defaults.object(forKey: Key.canvasBackgroundAnimated) != nil {
            settings.canvasBackgroundAnimated = defaults.bool(forKey: Key.canvasBackgroundAnimated)
        }
        if !settings.canvasBackgroundStyle.supportsBackgroundAnimation {
            settings.canvasBackgroundAnimated = false
        }
        if defaults.object(forKey: Key.canvasPadding) != nil {
            settings.canvasPadding = clampedCanvasPadding(defaults.double(forKey: Key.canvasPadding))
        }
        settings.sceneLayout = SceneLayout.defaultLayout(for: settings.layout)
        let savedScreenFrame = rect(for: Key.screenFrame, defaults: defaults)
        let savedCameraFrame = rect(for: Key.cameraFrame, defaults: defaults)
        if let frame = rect(for: Key.screenFrame, defaults: defaults) {
            settings.sceneLayout.screenFrame = frame
        }
        if let frame = rect(for: Key.cameraFrame, defaults: defaults) {
            settings.sceneLayout.cameraFrame = frame
        }
        if let rawPreset = defaults.string(forKey: Key.selectedScenePreset),
           let preset = ScenePreset(rawValue: rawPreset),
           preset.supports(settings.layout) {
            let presetLayout = SceneLayout.presetLayout(preset, for: settings.layout)
            let savedFramesMakeScreenSplit: Bool
            if preset == .screenTop50,
               settings.layout == .vertical,
               let savedScreenFrame,
               let savedCameraFrame {
                savedFramesMakeScreenSplit = SceneLayout(
                    screenFrame: savedScreenFrame,
                    cameraFrame: savedCameraFrame
                ).screenSplitHeight != nil
            } else {
                savedFramesMakeScreenSplit = false
            }
            let savedScreenFrameMatchesPreset = savedScreenFrame.map { rectAlmostEquals($0, presetLayout.screenFrame) } ?? true
            let savedCameraFrameMatchesPreset = savedCameraFrame.map { rectAlmostEquals($0, presetLayout.cameraFrame) } ?? true
            let savedFramesMatchPreset = savedScreenFrameMatchesPreset && savedCameraFrameMatchesPreset
            if savedFramesMakeScreenSplit {
                settings.selectedScenePreset = preset
            } else if savedFramesMatchPreset || legacyFramesMatchPreset(
                preset,
                layout: settings.layout,
                screenFrame: savedScreenFrame,
                cameraFrame: savedCameraFrame
            ) {
                settings.selectedScenePreset = preset
                settings.sceneLayout = presetLayout
            }
        }
        if defaults.string(forKey: Key.selectedScenePreset) == ScenePreset.cameraFocus.rawValue {
            settings.sceneLayout = SceneLayout.defaultLayout(for: settings.layout)
        }
        if let rawOrder = defaults.stringArray(forKey: Key.layerOrder) {
            let order = rawOrder.compactMap(SceneLayerKind.init(rawValue:))
            if Set(order) == Set(SceneLayerKind.allCases), order.count == SceneLayerKind.allCases.count {
                settings.sceneLayout.layerOrder = order
            }
        }
        if settings.layout == .vertical,
           rectAlmostEquals(settings.sceneLayout.screenFrame, CGRect(x: 0, y: 0.341796875, width: 1, height: 0.31640625)),
           rectAlmostEquals(settings.sceneLayout.cameraFrame, CGRect(x: 0, y: 0.046796875, width: 1, height: 0.31640625)) {
            settings.sceneLayout = SceneLayout.defaultLayout(for: .vertical)
        }
        if settings.layout == .vertical,
           settings.sceneLayout.screenFrame == CGRect(x: 0, y: 0.53, width: 1, height: 0.47),
           settings.sceneLayout.cameraFrame == CGRect(x: 0, y: 0, width: 1, height: 0.53) {
            settings.sceneLayout = SceneLayout.defaultLayout(for: .vertical)
        }
        if settings.layout == .vertical,
           settings.sceneLayout.screenFrame == CGRect(x: 0, y: 0.684, width: 1, height: 0.316),
           settings.sceneLayout.cameraFrame == CGRect(x: 0, y: 0, width: 1, height: 0.684) {
            settings.sceneLayout = SceneLayout.defaultLayout(for: .vertical)
        }
        if settings.layout == .vertical,
           settings.sceneLayout.screenFrame == CGRect(x: 0, y: 0, width: 1, height: 1) {
            settings.sceneLayout.screenFrame = SceneLayout.defaultLayout(for: .vertical).screenFrame
        }
        if settings.layout == .horizontal,
           settings.sceneLayout.screenFrame == CGRect(x: 0, y: 0, width: 1, height: 1),
           settings.sceneLayout.cameraFrame == CGRect(x: 0.685, y: 0.035, width: 0.28, height: 0.1575) {
            settings.sceneLayout = SceneLayout.defaultLayout(for: .horizontal)
        }

        if let storedBookmarkData = defaults.data(forKey: Key.outputDirectoryBookmark) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: storedBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                settings.outputDirectory = url
                settings.outputDirectoryBookmarkData = stale ? bookmarkData(for: url) : storedBookmarkData
            }
        } else if let path = defaults.string(forKey: Key.outputDirectoryPath), !path.isEmpty {
            settings.outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }

        settings.usesPickedScreenContent = false
        return settings
    }

    static func save(_ settings: RecordingSettings, defaults: UserDefaults? = nil) {
        let defaults = defaults ?? defaultStore()
        defaults.set(settings.layout.rawValue, forKey: Key.layout)
        defaults.set(settings.outputResolution.rawValue, forKey: Key.outputResolution)
        defaults.set(settings.outputVideoFormat.rawValue, forKey: Key.outputVideoFormat)
        defaults.set(settings.framesPerSecond, forKey: Key.framesPerSecond)
        if let customVideoBitrate = settings.customVideoBitrate {
            defaults.set(customVideoBitrate, forKey: Key.customVideoBitrate)
        } else {
            defaults.removeObject(forKey: Key.customVideoBitrate)
        }
        defaults.set(settings.audioQuality.rawValue, forKey: Key.audioQuality)
        defaults.set(settings.sourceAudioFormat.rawValue, forKey: Key.sourceAudioFormat)
        defaults.set(settings.microphoneGain, forKey: Key.microphoneGain)
        defaults.set(settings.systemAudioGain, forKey: Key.systemAudioGain)
        defaults.set(settings.removesCameraBackgroundAfterRecording, forKey: Key.removesCameraBackgroundAfterRecording)
        defaults.set(settings.savesSourceFiles, forKey: Key.savesSourceFiles)
        defaults.set(settings.renamesRecordingsFromSpeech, forKey: Key.renamesRecordingsFromSpeech)
        defaults.set(settings.showsRuleOfThirdsOverlay, forKey: Key.showsRuleOfThirdsOverlay)
        defaults.set(settings.socialSafeZoneOverlay.rawValue, forKey: Key.socialSafeZoneOverlay)
        defaults.set(settings.includeCursor, forKey: Key.includeCursor)
        defaults.set(settings.enabledSources.map(\.rawValue).sorted(), forKey: Key.enabledSources)
        defaults.set(settings.hiddenSources.map(\.rawValue).sorted(), forKey: Key.hiddenSources)
        if let screenSourceBinding = settings.screenSourceBinding,
           let data = try? JSONEncoder().encode(screenSourceBinding) {
            defaults.set(data, forKey: Key.screenSourceBinding)
        } else {
            defaults.removeObject(forKey: Key.screenSourceBinding)
        }
        defaults.set(settings.selectedDisplayID, forKey: Key.selectedDisplayID)
        defaults.set(settings.selectedCameraID, forKey: Key.selectedCameraID)
        defaults.set(settings.selectedMicrophoneID, forKey: Key.selectedMicrophoneID)
        defaults.set(settings.trustedRemoteCameraServiceIDs.sorted(), forKey: Key.trustedRemoteCameraServiceIDs)
        if let data = try? JSONEncoder().encode(settings.remoteCameraSettingsByServiceID) {
            defaults.set(data, forKey: Key.remoteCameraSettingsByServiceID)
        } else {
            defaults.removeObject(forKey: Key.remoteCameraSettingsByServiceID)
        }
        defaults.set(settings.outputDirectory.path, forKey: Key.outputDirectoryPath)
        if let bookmarkData = settings.outputDirectoryBookmarkData {
            defaults.set(bookmarkData, forKey: Key.outputDirectoryBookmark)
        } else {
            defaults.removeObject(forKey: Key.outputDirectoryBookmark)
        }
        if let screenCrop = settings.screenCrop {
            defaults.set(string(from: screenCrop), forKey: Key.screenCrop)
        } else {
            defaults.removeObject(forKey: Key.screenCrop)
        }
        defaults.set(string(from: settings.cameraCropAmount), forKey: Key.cameraCropAmount)
        defaults.set(string(from: settings.cameraCropPosition), forKey: Key.cameraCropPosition)
        defaults.set(settings.canvasBackgroundStyle.rawValue, forKey: Key.canvasBackgroundStyle)
        defaults.set(settings.canvasBackgroundAnimated, forKey: Key.canvasBackgroundAnimated)
        defaults.set(clampedCanvasPadding(Double(settings.canvasPadding)), forKey: Key.canvasPadding)
        defaults.set(string(from: settings.sceneLayout.screenFrame), forKey: Key.screenFrame)
        defaults.set(string(from: settings.sceneLayout.cameraFrame), forKey: Key.cameraFrame)
        defaults.set(settings.sceneLayout.layerOrder.map(\.rawValue), forKey: Key.layerOrder)
        if let preset = settings.selectedScenePreset {
            defaults.set(preset.rawValue, forKey: Key.selectedScenePreset)
        } else {
            defaults.removeObject(forKey: Key.selectedScenePreset)
        }
    }

    private static func rect(for key: String, defaults: UserDefaults) -> CGRect? {
        guard let string = defaults.string(forKey: key) else { return nil }
        let values = string.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private static func point(for key: String, defaults: UserDefaults) -> CGPoint? {
        guard let string = defaults.string(forKey: key) else { return nil }
        let values = string.split(separator: ",").compactMap { Double($0) }
        guard values.count == 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    private static func remoteCameraSettingsByServiceID(defaults: UserDefaults) -> [String: RemoteCameraSettings] {
        guard let data = defaults.data(forKey: Key.remoteCameraSettingsByServiceID),
              let settings = try? JSONDecoder().decode([String: RemoteCameraSettings].self, from: data) else {
            return [:]
        }
        return settings
    }

    private static func defaultStore() -> UserDefaults {
        .standard
    }

    static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func string(from rect: CGRect) -> String {
        "\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height)"
    }

    private static func string(from point: CGPoint) -> String {
        "\(point.x),\(point.y)"
    }

    private static func rectAlmostEquals(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let epsilon: CGFloat = 0.0001
        return abs(lhs.minX - rhs.minX) < epsilon
            && abs(lhs.minY - rhs.minY) < epsilon
            && abs(lhs.width - rhs.width) < epsilon
            && abs(lhs.height - rhs.height) < epsilon
    }

    private static func legacyFramesMatchPreset(
        _ preset: ScenePreset,
        layout: CaptureLayout,
        screenFrame: CGRect?,
        cameraFrame: CGRect?
    ) -> Bool {
        guard layout == .vertical,
              let screenFrame,
              let cameraFrame else {
            return false
        }

        if preset == .stackedHalves {
            return rectAlmostEquals(screenFrame, CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
            && rectAlmostEquals(cameraFrame, CGRect(x: 0, y: 0, width: 1, height: 0.5))
        }

        if preset == .webcamFullscreen {
            return rectAlmostEquals(cameraFrame, CGRect(x: 0, y: 0.341796875, width: 1, height: 0.31640625))
        }

        return false
    }

    private static func clampedGain(_ gain: Double) -> Double {
        min(2.0, max(0.0, gain))
    }

    private static func clampedCanvasPadding(_ padding: Double) -> CGFloat {
        CGFloat(min(0.16, max(0, padding)))
    }
}
