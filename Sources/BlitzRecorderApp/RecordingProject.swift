import CoreGraphics
import Foundation

struct SourceTakeManifest: Codable, Equatable {
    struct SourceFile: Codable, Equatable {
        let role: String
        let path: String
    }

    let version: Int
    let updatedAt: Date
    let layout: String
    let outputResolution: String
    let outputVideoFormat: String
    let framesPerSecond: Int
    let enabledSources: [String]
    let sources: [SourceFile]
    let finalVideoPath: String?
}

struct RecordingProject: Codable, Equatable {
    struct SourceFile: Codable, Equatable {
        let role: String
        let path: String
        let exists: Bool
    }

    struct SettingsSnapshot: Codable, Equatable {
        var layout: String
        let outputResolution: String
        let outputVideoFormat: String
        let framesPerSecond: Int
        let enabledSources: [String]
        let hiddenSources: [String]
        let microphoneGain: Double?
        let systemAudioGain: Double?
        let canvasBackgroundStyle: String
        let canvasBackgroundAnimated: Bool
        let canvasPadding: Double
        let screenCornerRadius: Double?
        let screenShadowEnabled: Bool?
        let screenContentMode: String?
        let cameraContentMode: String
        let cameraFramePadding: Double
        let cameraShadowEnabled: Bool
    }

    struct ExportRecord: Codable, Equatable, Identifiable {
        let id: UUID
        let createdAt: Date
        let path: String
        let format: String
        let resolution: String
        let framesPerSecond: Int
        let quality: String
        let fileSizeBytes: Int64?
        var layout: String? = nil
        var width: Int? = nil
        var height: Int? = nil
    }

    let version: Int
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let projectPath: String
    let takeDirectoryPath: String
    let finalVideoPath: String?
    let timelineTrimOffsetSeconds: Double
    let sourceTimelineOffsetSeconds: [String: Double]
    var settings: SettingsSnapshot
    let sources: [SourceFile]
    var sceneEvents: [SceneEventSnapshot]
    let chapters: [ChapterSnapshot]
    let editorTimeline: TimelineSnapshot
    let editorState: EditorStateSnapshot
    let exports: [ExportRecord]
    var timelineEdits: TimelineEditsSnapshot
    let analysis: AnalysisSnapshot

    enum CodingKeys: String, CodingKey {
        case version
        case id
        case createdAt
        case updatedAt
        case title
        case projectPath
        case takeDirectoryPath
        case finalVideoPath
        case timelineTrimOffsetSeconds
        case sourceTimelineOffsetSeconds
        case settings
        case sources
        case sceneEvents
        case chapters
        case editorTimeline = "timeline"
        case editorState
        case exports
        case timelineEdits
        case analysis
        case cuts
        case scene
    }

    init(
        version: Int,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        title: String,
        projectPath: String,
        takeDirectoryPath: String,
        finalVideoPath: String?,
        settings: SettingsSnapshot,
        sources: [SourceFile],
        sceneEvents: [SceneEventSnapshot],
        chapters: [ChapterSnapshot] = [],
        editorTimeline: TimelineSnapshot = .empty,
        editorState: EditorStateSnapshot = .empty,
        exports: [ExportRecord] = [],
        timelineTrimOffsetSeconds: Double = 0,
        sourceTimelineOffsetSeconds: [String: Double] = [:],
        timelineEdits: TimelineEditsSnapshot = .empty,
        analysis: AnalysisSnapshot = .empty
    ) {
        self.timelineEdits = timelineEdits
        self.analysis = analysis
        self.version = version
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.projectPath = projectPath
        self.takeDirectoryPath = takeDirectoryPath
        self.finalVideoPath = finalVideoPath
        self.timelineTrimOffsetSeconds = timelineTrimOffsetSeconds
        self.sourceTimelineOffsetSeconds = sourceTimelineOffsetSeconds
        self.settings = settings
        self.sources = sources
        self.sceneEvents = sceneEvents
        self.chapters = chapters
        self.editorTimeline = editorTimeline
        self.editorState = editorState
        self.exports = exports
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.title = try container.decode(String.self, forKey: .title)
        self.projectPath = try container.decode(String.self, forKey: .projectPath)
        self.takeDirectoryPath = try container.decode(String.self, forKey: .takeDirectoryPath)
        self.finalVideoPath = try container.decodeIfPresent(String.self, forKey: .finalVideoPath)
        self.timelineTrimOffsetSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .timelineTrimOffsetSeconds
        ) ?? 0
        self.sourceTimelineOffsetSeconds = try container.decodeIfPresent(
            [String: Double].self,
            forKey: .sourceTimelineOffsetSeconds
        ) ?? [:]
        self.settings = try container.decode(SettingsSnapshot.self, forKey: .settings)
        self.sources = try container.decode([SourceFile].self, forKey: .sources)
        self.sceneEvents = try container.decode([SceneEventSnapshot].self, forKey: .sceneEvents)
        self.chapters = try container.decodeIfPresent([ChapterSnapshot].self, forKey: .chapters) ?? []
        self.editorTimeline = try container.decodeIfPresent(TimelineSnapshot.self, forKey: .editorTimeline) ?? .empty
        self.editorState = try container.decodeIfPresent(EditorStateSnapshot.self, forKey: .editorState) ?? .empty
        self.exports = try container.decodeIfPresent([ExportRecord].self, forKey: .exports) ?? []
        self.timelineEdits = try container.decodeIfPresent(TimelineEditsSnapshot.self, forKey: .timelineEdits) ?? .empty
        self.analysis = try container.decodeIfPresent(AnalysisSnapshot.self, forKey: .analysis) ?? .empty
        _ = try container.decodeIfPresent([TimelineCut].self, forKey: .cuts)
        _ = try container.decodeIfPresent(PortableSceneLayout.self, forKey: .scene)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(title, forKey: .title)
        try container.encode(projectPath, forKey: .projectPath)
        try container.encode(takeDirectoryPath, forKey: .takeDirectoryPath)
        try container.encodeIfPresent(finalVideoPath, forKey: .finalVideoPath)
        try container.encode(timelineTrimOffsetSeconds, forKey: .timelineTrimOffsetSeconds)
        try container.encode(sourceTimelineOffsetSeconds, forKey: .sourceTimelineOffsetSeconds)
        try container.encode(settings, forKey: .settings)
        try container.encode(sources, forKey: .sources)
        try container.encode(sceneEvents, forKey: .sceneEvents)
        try container.encode(chapters, forKey: .chapters)
        try container.encode(editorTimeline, forKey: .editorTimeline)
        try container.encode(editorState, forKey: .editorState)
        try container.encode(exports, forKey: .exports)
        if !timelineEdits.isEmpty {
            try container.encode(timelineEdits, forKey: .timelineEdits)
        }
        if !analysis.isEmpty {
            try container.encode(analysis, forKey: .analysis)
        }
        try container.encode(timelineEdits.edits.cuts, forKey: .cuts)
        try container.encode(portableSceneLayout, forKey: .scene)
    }

    var portableSceneLayout: PortableSceneLayout {
        guard let snapshot = sceneEvents.last?.scene else {
            return .screenOnly
        }
        let screen = snapshot.sceneLayout.screenFrame.rect
        let camera = snapshot.sceneLayout.cameraFrame.rect
        let cameraOn = snapshot.enabledSources.contains(CaptureSource.camera.rawValue)
        return PortableSceneLayout(
            canvasWidth: PortableSceneLayout.defaultCanvasWidth,
            canvasHeight: PortableSceneLayout.defaultCanvasHeight,
            screen: NormalizedRect(
                x: screen.minX,
                y: screen.minY,
                width: screen.width,
                height: screen.height
            ),
            camera: cameraOn
                ? NormalizedRect(
                    x: camera.minX,
                    y: camera.minY,
                    width: camera.width,
                    height: camera.height
                )
                : nil,
            cameraShape: snapshot.sceneLayout.sceneCameraMask.portableShape
        )
    }

    var edits: TimelineEdits {
        timelineEdits.edits
    }

    static func importedPortable(from data: Data, projectURL: URL) throws -> RecordingProject {
        let portable = try JSONDecoder().decode(PortableProject.self, from: data)
        let takeDir = projectURL.deletingLastPathComponent()
        let manifest = try? TakeJSON.read(
            TakeManifest.self,
            from: takeDir.appendingPathComponent(TakeFolderLayout.takeManifestName)
        )
        let now = Date()
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.enabledSources = Set(portable.sources.compactMap { captureSource(forPortableRole: $0.role) })
        if settings.enabledSources.intersection([.screen, .camera]).isEmpty {
            settings.enabledSources.insert(.screen)
        }
        settings.sceneLayout.screenFrame = CGRect(
            x: portable.scene.screen.x,
            y: portable.scene.screen.y,
            width: portable.scene.screen.width,
            height: portable.scene.screen.height
        )
        if let camera = portable.scene.camera ?? (portable.hasCamera ? NormalizedRect.cameraPip : nil) {
            settings.sceneLayout.cameraFrame = CGRect(
                x: camera.x,
                y: camera.y,
                width: camera.width,
                height: camera.height
            )
        }
        settings.sceneLayout.cameraMask = SceneCameraMask(portable.scene.cameraShape)
        var edits = TimelineEdits.empty
        edits.cuts = portable.cuts
        let sources = portable.sources.map { source -> SourceFile in
            let absolute = takeDir.appendingPathComponent(source.path)
            let exists = FileManager.default.fileExists(atPath: absolute.path)
            return SourceFile(role: source.role, path: exists ? absolute.path : source.path, exists: exists)
        }
        let exported = takeDir.appendingPathComponent(TakeFolderLayout.exportName)
        return RecordingProject(
            version: portable.version,
            id: manifest?.id ?? UUID(),
            createdAt: manifest?.createdAt ?? now,
            updatedAt: now,
            title: takeDir.lastPathComponent,
            projectPath: projectURL.path,
            takeDirectoryPath: takeDir.path,
            finalVideoPath: FileManager.default.fileExists(atPath: exported.path) ? exported.path : nil,
            settings: SettingsSnapshot(settings),
            sources: sources,
            sceneEvents: [SceneEventSnapshot(RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings)))],
            timelineEdits: TimelineEditsSnapshot(edits)
        )
    }

    static func captureSource(forPortableRole role: String) -> CaptureSource? {
        switch role {
        case "screen":
            return .screen
        case "camera":
            return .camera
        case "microphone":
            return .microphone
        case "systemAudio":
            return .systemAudio
        default:
            return CaptureSource(rawValue: role)
        }
    }
}

extension RecordingProject.SettingsSnapshot {
    init(_ settings: RecordingSettings) {
        self.layout = settings.layout.rawValue
        self.outputResolution = settings.outputResolution.rawValue
        self.outputVideoFormat = settings.outputVideoFormat.rawValue
        self.framesPerSecond = settings.framesPerSecond
        self.enabledSources = settings.enabledSources.map(\.rawValue).sorted()
        self.hiddenSources = settings.hiddenSources.map(\.rawValue).sorted()
        self.microphoneGain = settings.microphoneGain
        self.systemAudioGain = settings.systemAudioGain
        self.canvasBackgroundStyle = settings.canvasBackgroundStyle.rawValue
        self.canvasBackgroundAnimated = settings.canvasBackgroundAnimated
        self.canvasPadding = Double(settings.canvasPadding)
        self.screenCornerRadius = Double(settings.screenCornerRadius)
        self.screenShadowEnabled = settings.screenShadowEnabled
        self.screenContentMode = settings.screenContentMode.rawValue
        self.cameraContentMode = settings.cameraContentMode.rawValue
        self.cameraFramePadding = Double(settings.cameraFramePadding)
        self.cameraShadowEnabled = settings.cameraShadowEnabled
    }
}
