import CoreGraphics
import CoreMedia
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
        let layout: String
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

    struct RectValue: Codable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: CGRect) {
            self.x = Double(rect.minX)
            self.y = Double(rect.minY)
            self.width = Double(rect.width)
            self.height = Double(rect.height)
        }
    }

    struct PointValue: Codable, Equatable {
        let x: Double
        let y: Double

        init(_ point: CGPoint) {
            self.x = Double(point.x)
            self.y = Double(point.y)
        }
    }

    struct SceneLayoutSnapshot: Codable, Equatable {
        let screenFrame: RectValue
        let cameraFrame: RectValue
        let layerOrder: [String]

        init(_ layout: SceneLayout) {
            self.screenFrame = RectValue(layout.screenFrame)
            self.cameraFrame = RectValue(layout.cameraFrame)
            self.layerOrder = layout.layerOrder.map(\.rawValue)
        }
    }

    struct ScreenSourceSnapshot: Codable, Equatable {
        let usesPickedContent: Bool
        let fillsSceneFrame: Bool?
        let selectedDisplayID: String?
        let normalizedCrop: RectValue?
        let sourceAspectRatio: Double?

        init(_ geometry: ScreenSourceGeometry) {
            self.usesPickedContent = geometry.usesPickedContent
            self.fillsSceneFrame = geometry.fillsSceneFrame
            self.selectedDisplayID = geometry.selectedDisplayID
            self.normalizedCrop = geometry.normalizedCrop.map(RectValue.init)
            self.sourceAspectRatio = geometry.sourceAspectRatio.map(Double.init)
        }
    }

    struct SceneSnapshot: Codable, Equatable {
        let enabledSources: [String]
        let sceneLayout: SceneLayoutSnapshot
        let screenSourceGeometry: ScreenSourceSnapshot
        let screenCropAmount: PointValue?
        let screenCropPosition: PointValue?
        let cameraCropAmount: PointValue
        let cameraCropPosition: PointValue
        let canvasBackgroundStyle: String
        let canvasBackgroundAnimated: Bool
        let canvasPadding: Double
        let screenCornerRadius: Double?
        let screenShadowEnabled: Bool?
        let screenContentMode: String?
        let cameraContentMode: String
        let cameraFramePadding: Double
        let cameraShadowEnabled: Bool
        let sourceOpacities: [String: Double]

        init(_ scene: RecordingScene) {
            self.enabledSources = scene.enabledSources.map(\.rawValue).sorted()
            self.sceneLayout = SceneLayoutSnapshot(scene.sceneLayout)
            self.screenSourceGeometry = ScreenSourceSnapshot(scene.screenSourceGeometry)
            self.screenCropAmount = PointValue(scene.screenCropAmount)
            self.screenCropPosition = PointValue(scene.screenCropPosition)
            self.cameraCropAmount = PointValue(scene.cameraCropAmount)
            self.cameraCropPosition = PointValue(scene.cameraCropPosition)
            self.canvasBackgroundStyle = scene.canvasBackgroundStyle.rawValue
            self.canvasBackgroundAnimated = scene.canvasBackgroundAnimated
            self.canvasPadding = Double(scene.canvasPadding)
            self.screenCornerRadius = Double(scene.screenCornerRadius)
            self.screenShadowEnabled = scene.screenShadowEnabled
            self.screenContentMode = scene.screenContentMode.rawValue
            self.cameraContentMode = scene.cameraContentMode.rawValue
            self.cameraFramePadding = Double(scene.cameraFramePadding)
            self.cameraShadowEnabled = scene.cameraShadowEnabled
            self.sourceOpacities = Dictionary(uniqueKeysWithValues: scene.sourceOpacities.map { source, opacity in
                (source.rawValue, Double(opacity))
            })
        }
    }

    struct TransitionSnapshot: Codable, Equatable {
        let duration: Double
        let curve: String

        init(_ transition: RecordingSceneTransition) {
            self.duration = transition.duration
            switch transition.curve {
            case .linear:
                self.curve = "linear"
            case .easeInOut:
                self.curve = "easeInOut"
            }
        }
    }

    struct SceneEventSnapshot: Codable, Equatable {
        let time: Double
        let scene: SceneSnapshot
        let transition: TransitionSnapshot

        init(_ event: RecordingSceneEvent) {
            self.time = event.time
            self.scene = SceneSnapshot(event.scene)
            self.transition = TransitionSnapshot(event.transition)
        }
    }

    struct ChapterSnapshot: Codable, Equatable, Identifiable {
        let id: UUID
        let time: Double
        let endTime: Double?
        let title: String
        let summary: String?
        let confidence: Double?

        init(
            id: UUID = UUID(),
            time: Double,
            endTime: Double? = nil,
            title: String,
            summary: String? = nil,
            confidence: Double? = nil
        ) {
            self.id = id
            self.time = time
            self.endTime = endTime
            self.title = title
            self.summary = summary
            self.confidence = confidence
        }
    }

    struct TimelineSnapshot: Codable, Equatable {
        struct Track: Codable, Equatable, Identifiable {
            let id: String
            let kind: String
            let title: String
            let sourceRole: String?
        }

        struct Clip: Codable, Equatable, Identifiable {
            let id: String
            let trackID: String
            let sourceRole: String?
            let time: Double
            let duration: Double?
            let startOffset: Double
            let frame: RectValue?
            let crop: RectValue?
            let opacity: Double?
            let layerOrder: Int?
        }

        struct Keyframe: Codable, Equatable, Identifiable {
            let id: String
            let clipID: String
            let property: String
            let time: Double
            let value: Double
            let easing: String?
        }

        let tracks: [Track]
        let clips: [Clip]
        let keyframes: [Keyframe]

        static let empty = TimelineSnapshot(tracks: [], clips: [], keyframes: [])
    }

    struct ExportRecipeSnapshot: Codable, Equatable {
        let preset: String
        let format: String
        let resolution: String
        let framesPerSecond: Int
        let quality: String
    }

    struct EditorStateSnapshot: Codable, Equatable {
        let hiddenVideoSources: [String]
        let mutedAudioSources: [String]
        let backgroundMusicPath: String?
        let backgroundMusicBookmarkData: Data?
        let backgroundMusicVolume: Double?
        let exportRecipe: ExportRecipeSnapshot?

        static let empty = EditorStateSnapshot(
            hiddenVideoSources: [],
            mutedAudioSources: [],
            backgroundMusicPath: nil,
            backgroundMusicBookmarkData: nil,
            backgroundMusicVolume: nil,
            exportRecipe: nil
        )
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
    let settings: SettingsSnapshot
    let sources: [SourceFile]
    let sceneEvents: [SceneEventSnapshot]
    let chapters: [ChapterSnapshot]
    let editorTimeline: TimelineSnapshot
    let editorState: EditorStateSnapshot
    let exports: [ExportRecord]

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
        sourceTimelineOffsetSeconds: [String: Double] = [:]
    ) {
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
    }
}

struct RecordingProjectHistory: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: UUID
        let title: String
        let projectPath: String
        let takeDirectoryPath: String
        let finalVideoPath: String?
        let createdAt: Date?
        let updatedAt: Date
        let exports: [RecordingProject.ExportRecord]?
    }

    let version: Int
    var entries: [Entry]
}

enum RecordingProjectDisplayTitle {
    static func isUntitled(_ rawTitle: String) -> Bool {
        timestampDate(from: rawTitle) != nil
    }

    static func make(rawTitle: String, createdAt: Date) -> String {
        guard isUntitled(rawTitle) else { return rawTitle }
        return "Recording at \(createdAt.formatted(date: .omitted, time: .shortened))"
    }

    static func timestampDate(from rawTitle: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.date(from: String(rawTitle.prefix(19)))
    }
}

extension RecordingProject {
    var displayTitle: String {
        RecordingProjectDisplayTitle.make(rawTitle: title, createdAt: createdAt)
    }
}

extension RecordingProjectHistory.Entry {
    var displayTitle: String {
        let recordingDate = createdAt
            ?? RecordingProjectDisplayTitle.timestampDate(from: title)
            ?? updatedAt
        return RecordingProjectDisplayTitle.make(rawTitle: title, createdAt: recordingDate)
    }
}

enum RecordingProjectDeletionDisposition {
    case trash
    case permanent
}

struct RecordingProjectDeletionRequest {
    let project: RecordingProjectHistory.Entry
    let settings: RecordingSettings
    let disposition: RecordingProjectDeletionDisposition
}

struct RecordingProjectRenameRequest {
    let projectURL: URL
    let title: String
    let settings: RecordingSettings
}

struct RecordingProjectSceneRestoreRequest {
    let projectURL: URL
    let snapshot: RecordingProject
    let baseSettings: RecordingSettings
}

struct RecordingProjectEditorStateUpdateRequest {
    let projectURL: URL
    let editorState: RecordingProject.EditorStateSnapshot
    let baseSettings: RecordingSettings
}

private struct ProjectHistoryWriteRequest {
    let history: RecordingProjectHistory
    let settings: RecordingSettings
}

enum RecordingProjectSceneCorrection: String, CaseIterable {
    case screenOnly
    case cameraOnly
    case screenAndCamera

    var displayName: String {
        switch self {
        case .screenOnly:
            return "Screen"
        case .cameraOnly:
            return "Camera"
        case .screenAndCamera:
            return "Screen + Camera"
        }
    }

    var symbolName: String {
        switch self {
        case .screenOnly:
            return "display"
        case .cameraOnly:
            return "video"
        case .screenAndCamera:
            return "pip"
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

private extension RecordingSceneTransition {
    init(snapshot: RecordingProject.TransitionSnapshot) {
        let curve: RecordingSceneTransitionCurve
        switch snapshot.curve {
        case "linear":
            curve = .linear
        default:
            curve = .easeInOut
        }
        self.init(duration: snapshot.duration, curve: curve)
    }
}

extension RecordingScene {
    init?(snapshot: RecordingProject.SceneSnapshot) {
        let enabledSources = Set(snapshot.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        let layerOrder = snapshot.sceneLayout.layerOrder.compactMap(SceneLayerKind.init(rawValue:))
        self.init(
            enabledSources: enabledSources,
            sceneLayout: SceneLayout(
                screenFrame: CGRect(snapshot.sceneLayout.screenFrame),
                cameraFrame: CGRect(snapshot.sceneLayout.cameraFrame),
                layerOrder: layerOrder.isEmpty ? [.screen, .camera] : layerOrder
            ),
            screenSourceGeometry: ScreenSourceGeometry(
                usesPickedContent: snapshot.screenSourceGeometry.usesPickedContent,
                fillsSceneFrame: snapshot.screenSourceGeometry.fillsSceneFrame ?? false,
                selectedDisplayID: snapshot.screenSourceGeometry.selectedDisplayID,
                normalizedCrop: snapshot.screenSourceGeometry.normalizedCrop.map(CGRect.init),
                sourceAspectRatio: snapshot.screenSourceGeometry.sourceAspectRatio.map { CGFloat($0) }
            ),
            screenCropAmount: snapshot.screenCropAmount.map(CGPoint.init) ?? .zero,
            screenCropPosition: snapshot.screenCropPosition.map(CGPoint.init) ?? .zero,
            cameraCropAmount: CGPoint(snapshot.cameraCropAmount),
            cameraCropPosition: CGPoint(snapshot.cameraCropPosition),
            canvasBackgroundStyle: CanvasBackgroundStyle(rawValue: snapshot.canvasBackgroundStyle) ?? .black,
            canvasBackgroundAnimated: snapshot.canvasBackgroundAnimated,
            canvasPadding: CGFloat(snapshot.canvasPadding),
            screenCornerRadius: CGFloat(snapshot.screenCornerRadius ?? 0),
            screenShadowEnabled: snapshot.screenShadowEnabled ?? false,
            screenContentMode: snapshot.screenContentMode.flatMap(CameraContentMode.init(rawValue:)) ?? .fill,
            cameraContentMode: CameraContentMode(rawValue: snapshot.cameraContentMode) ?? .fill,
            cameraFramePadding: 0,
            cameraShadowEnabled: snapshot.cameraShadowEnabled,
            sourceOpacities: Dictionary(uniqueKeysWithValues: snapshot.sourceOpacities.compactMap { key, value in
                guard let source = CaptureSource(rawValue: key) else { return nil }
                return (source, CGFloat(value))
            })
        )
    }

    func corrected(
        _ correction: RecordingProjectSceneCorrection,
        layout: CaptureLayout
    ) -> RecordingScene {
        var scene = self
        let audioSources = enabledSources.filter { $0 == .microphone || $0 == .systemAudio }
        let videoSources: Set<CaptureSource>
        let preset: ScenePreset

        switch correction {
        case .screenOnly:
            videoSources = [.screen]
            preset = .screenFullscreen
        case .cameraOnly:
            videoSources = [.camera]
            preset = .webcamFullscreen
        case .screenAndCamera:
            videoSources = [.screen, .camera]
            preset = layout == .vertical ? .screenTop50 : .cameraInset
        }

        scene.enabledSources = audioSources.union(videoSources)
        scene.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: layout,
            screenAspectRatio: scene.screenSourceGeometry.aspectRatio()
        )
        scene.sourceOpacities = scene.sourceOpacities.filter { source, _ in
            scene.enabledSources.contains(source)
        }
        return scene
    }
}

private extension CGRect {
    init(_ value: RecordingProject.RectValue) {
        self.init(x: value.x, y: value.y, width: value.width, height: value.height)
    }
}

private extension CGPoint {
    init(_ value: RecordingProject.PointValue) {
        self.init(x: value.x, y: value.y)
    }
}

final class OutputDirectoryAccess {
    private let url: URL
    private let shouldStopAccessing: Bool
    private var isStopped = false
    let needsSecurityScopedAccess: Bool

    init(url: URL, usesSecurityScopedBookmark: Bool) {
        self.url = url
        self.needsSecurityScopedAccess = usesSecurityScopedBookmark
        shouldStopAccessing = usesSecurityScopedBookmark && url.startAccessingSecurityScopedResource()
    }

    var hasSecurityScopedAccess: Bool {
        !needsSecurityScopedAccess || shouldStopAccessing
    }

    deinit {
        stop()
    }

    func stop() {
        guard shouldStopAccessing, !isStopped else { return }
        url.stopAccessingSecurityScopedResource()
        isStopped = true
    }
}

struct TakeFileStore {
    static let minimumAvailableCapacityBytes: Int64 = 512 * 1024 * 1024

    func prepareOutputDirectory(settings: RecordingSettings) throws -> OutputDirectoryAccess {
        let access = OutputDirectoryAccess(
            url: settings.outputDirectory,
            usesSecurityScopedBookmark: settings.outputDirectoryBookmarkData != nil
        )
        guard access.hasSecurityScopedAccess else {
            access.stop()
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: settings.outputDirectory))
        }

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: settings.outputDirectory,
                withIntermediateDirectories: true
            )

            let scratchRoot = scratchRoot(for: settings)
            try fileManager.createDirectory(at: scratchRoot, withIntermediateDirectories: true)

            let probeURL = scratchRoot.appendingPathComponent(".write-test-\(UUID().uuidString)")
            try Data().write(to: probeURL, options: .atomic)
            try fileManager.removeItem(at: probeURL)
            let resourceValues = try settings.outputDirectory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
            )
            let fileSystemCapacity = Self.fileSystemAvailableCapacity(for: settings.outputDirectory)
            let capacity = Self.availableCapacityForRecording(
                importantUsageCapacity: resourceValues.volumeAvailableCapacityForImportantUsage,
                fallbackCapacity: resourceValues.volumeAvailableCapacity.map(Int64.init),
                fileSystemCapacity: fileSystemCapacity
            )
            if let capacity, capacity < Self.minimumAvailableCapacityBytes {
                throw RecorderError.outputDirectoryUnavailable(
                    "\(Self.formattedByteCount(capacity)) available; at least 512 MB required"
                )
            }
            if let contents = try? fileManager.contentsOfDirectory(atPath: scratchRoot.path),
               contents.isEmpty {
                try? fileManager.removeItem(at: scratchRoot)
            }

            return access
        } catch let error as RecorderError {
            access.stop()
            throw error
        } catch {
            access.stop()
            throw RecorderError.outputDirectoryUnavailable(Self.outputDirectoryFailureMessage(error, url: settings.outputDirectory))
        }
    }

    private static func outputDirectoryFailureMessage(_ error: Error, url: URL) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           (nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError) {
            return permissionRecoveryMessage(for: url)
        }

        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("permission") || lowercased.contains("operation not permitted") {
            return permissionRecoveryMessage(for: url)
        }
        return message
    }

    private static func permissionRecoveryMessage(for url: URL) -> String {
        "BlitzRecorder does not have permission to save to \(url.path). Choose this folder again in Export Settings, or pick another recording folder."
    }

    static func availableCapacityForRecording(
        importantUsageCapacity: Int64?,
        fallbackCapacity: Int64?,
        fileSystemCapacity: Int64? = nil
    ) -> Int64? {
        let reportedCapacities = [importantUsageCapacity, fallbackCapacity, fileSystemCapacity]
            .compactMap { $0 }
            .filter { $0 > 0 }
        if let capacity = reportedCapacities.max() {
            return capacity
        }
        return importantUsageCapacity ?? fallbackCapacity ?? fileSystemCapacity
    }

    private static func fileSystemAvailableCapacity(for url: URL) -> Int64? {
        guard let value = try? FileManager.default.attributesOfFileSystem(forPath: url.path)[.systemFreeSize] else {
            return nil
        }
        return (value as? NSNumber)?.int64Value
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    func createTake(settings: RecordingSettings, date: Date = Date()) throws -> RecordingTake {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

        let scratchRoot = scratchRoot(for: settings)
        let directory = scratchRoot
            .appendingPathComponent(formatter.string(from: date), isDirectory: true)
        let scratchDirectory = uniqueDirectory(directory)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

        let take = RecordingTake(
            scratchDirectory: scratchDirectory,
            screenURL: scratchDirectory.appendingPathComponent("screen.\(settings.sourceVideoFormat.fileExtension)"),
            cameraURL: scratchDirectory.appendingPathComponent("camera.\(settings.sourceVideoFormat.fileExtension)"),
            audioURL: scratchDirectory.appendingPathComponent("audio.\(settings.effectiveSourceAudioFormat.fileExtension)"),
            systemAudioURL: scratchDirectory.appendingPathComponent("system-audio.\(settings.effectiveSourceAudioFormat.fileExtension)"),
            transcriptURL: scratchDirectory.appendingPathComponent("transcript.txt"),
            finalVideoURL: finalVideoURL(
                slug: Self.defaultSlug(for: scratchDirectory),
                settings: settings,
                outputFormat: settings.outputVideoFormat
            ),
            outputVideoFormat: settings.outputVideoFormat,
            titleSlug: nil
        )
        if settings.savesSourceFiles {
            try writeSourceTakeManifest(for: take, settings: settings, finalVideoURL: nil)
            try writeRecordingProject(
                for: take,
                settings: settings,
                sceneEvents: [RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))],
                finalVideoURL: nil
            )
        }
        return take
    }

    func cleanupIntermediateFiles(for take: RecordingTake, settings: RecordingSettings) {
        try? FileManager.default.removeItem(at: take.scratchDirectory)
        let scratchRoot = scratchRoot(for: settings)
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: scratchRoot.path),
           contents.isEmpty {
            try? FileManager.default.removeItem(at: scratchRoot)
        }
    }

    func writeSourceTakeManifest(
        for take: RecordingTake,
        settings: RecordingSettings,
        finalVideoURL: URL?
    ) throws {
        let manifest = SourceTakeManifest(
            version: 1,
            updatedAt: Date(),
            layout: settings.layout.rawValue,
            outputResolution: settings.outputResolution.rawValue,
            outputVideoFormat: settings.outputVideoFormat.rawValue,
            framesPerSecond: settings.framesPerSecond,
            enabledSources: settings.enabledSources
                .map(\.rawValue)
                .sorted(),
            sources: sourceFiles(for: take),
            finalVideoPath: finalVideoURL?.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: take.sourceManifestURL, options: .atomic)
    }

    func writeRecordingProject(
        for take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        finalVideoURL: URL?,
        chapters: [RecordingProject.ChapterSnapshot] = [],
        editorTimeline: RecordingProject.TimelineSnapshot = .empty,
        editorState: RecordingProject.EditorStateSnapshot? = nil,
        exportRecord: RecordingProject.ExportRecord? = nil
    ) throws {
        let now = Date()
        let projectURL = take.projectURL
        let existingProject = try? loadRecordingProject(at: projectURL)
        var exports = existingProject?.exports ?? []
        if let exportRecord {
            exports.removeAll { $0.path == exportRecord.path }
            exports.append(exportRecord)
            exports.sort { $0.createdAt < $1.createdAt }
        }
        let project = RecordingProject(
            version: 1,
            id: projectID(for: take, projectURL: projectURL),
            createdAt: projectCreatedAt(for: take, fallback: now),
            updatedAt: now,
            title: take.titleSlug ?? Self.defaultSlug(for: take.scratchDirectory),
            projectPath: projectURL.path,
            takeDirectoryPath: take.scratchDirectory.path,
            finalVideoPath: finalVideoURL?.path,
            settings: RecordingProject.SettingsSnapshot(settings),
            sources: projectSourceFiles(for: take),
            sceneEvents: sceneEvents.map(RecordingProject.SceneEventSnapshot.init),
            chapters: chapters,
            editorTimeline: editorTimeline,
            editorState: editorState ?? existingProject?.editorState ?? .empty,
            exports: exports,
            timelineTrimOffsetSeconds: max(0, take.timelineTrimOffset.seconds),
            sourceTimelineOffsetSeconds: Dictionary(uniqueKeysWithValues: take.sourceTimelineOffsets.map {
                ($0.key.rawValue, max(0, $0.value.seconds))
            })
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: projectURL, options: .atomic)
        try upsertProjectHistory(project, settings: settings)
    }

    func loadProjectHistory(settings: RecordingSettings) -> RecordingProjectHistory {
        let url = projectHistoryURL(for: settings)
        guard let data = try? Data(contentsOf: url) else {
            return RecordingProjectHistory(version: 1, entries: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RecordingProjectHistory.self, from: data))
            ?? RecordingProjectHistory(version: 1, entries: [])
    }

    func loadRecordingProject(at url: URL) throws -> RecordingProject {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingProject.self, from: data)
    }

    func renameProject(
        _ request: RecordingProjectRenameRequest
    ) throws -> RecordingProject {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw RecorderError.mediaWriteFailed("Enter a recording title.")
        }

        let project = try loadRecordingProject(at: request.projectURL)
        let renamedProject = RecordingProject(
            version: project.version,
            id: project.id,
            createdAt: project.createdAt,
            updatedAt: Date(),
            title: title,
            projectPath: project.projectPath,
            takeDirectoryPath: project.takeDirectoryPath,
            finalVideoPath: project.finalVideoPath,
            settings: project.settings,
            sources: project.sources,
            sceneEvents: project.sceneEvents,
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: project.editorState,
            exports: project.exports,
            timelineTrimOffsetSeconds: project.timelineTrimOffsetSeconds,
            sourceTimelineOffsetSeconds: project.sourceTimelineOffsetSeconds
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(renamedProject).write(
            to: request.projectURL,
            options: .atomic
        )
        try upsertProjectHistory(renamedProject, settings: request.settings)
        return renamedProject
    }

    func deleteProject(_ request: RecordingProjectDeletionRequest) throws {
        let fileManager = FileManager.default
        let outputDirectoryAccess = OutputDirectoryAccess(
            url: request.settings.outputDirectory,
            usesSecurityScopedBookmark: request.settings.outputDirectoryBookmarkData != nil
        )
        guard outputDirectoryAccess.hasSecurityScopedAccess else {
            outputDirectoryAccess.stop()
            throw RecorderError.outputDirectoryUnavailable(
                Self.permissionRecoveryMessage(for: request.settings.outputDirectory)
            )
        }
        defer {
            outputDirectoryAccess.stop()
        }

        let projectDirectory = URL(
            fileURLWithPath: request.project.takeDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        let projectsRoot = scratchRoot(for: request.settings).standardizedFileURL
        let projectsRootPrefix = projectsRoot.path.hasSuffix("/")
            ? projectsRoot.path
            : projectsRoot.path + "/"

        guard projectDirectory.path.hasPrefix(projectsRootPrefix) else {
            throw RecorderError.mediaWriteFailed(
                "This project is outside the BlitzRecorder source projects folder."
            )
        }

        if fileManager.fileExists(atPath: projectDirectory.path) {
            switch request.disposition {
            case .trash:
                try fileManager.trashItem(at: projectDirectory, resultingItemURL: nil)
            case .permanent:
                try fileManager.removeItem(at: projectDirectory)
            }
        }

        var history = loadProjectHistory(settings: request.settings)
        history.entries.removeAll {
            $0.id == request.project.id || $0.projectPath == request.project.projectPath
        }
        try writeProjectHistory(ProjectHistoryWriteRequest(
            history: history,
            settings: request.settings
        ))
    }

    func recordingTake(
        from project: RecordingProject,
        settings: RecordingSettings,
        outputFormat: OutputVideoFormat
    ) -> RecordingTake {
        let scratchDirectory = URL(fileURLWithPath: project.takeDirectoryPath, isDirectory: true)
        let sourceURLByRole = Dictionary(uniqueKeysWithValues: project.sources.map { ($0.role, URL(fileURLWithPath: $0.path)) })
        return RecordingTake(
            scratchDirectory: scratchDirectory,
            screenURL: sourceURLByRole["screen"] ?? scratchDirectory.appendingPathComponent("screen.mov"),
            cameraURL: sourceURLByRole["camera"] ?? scratchDirectory.appendingPathComponent("camera.mov"),
            audioURL: sourceURLByRole["microphone"] ?? scratchDirectory.appendingPathComponent("audio.m4a"),
            systemAudioURL: sourceURLByRole["systemAudio"] ?? scratchDirectory.appendingPathComponent("system-audio.m4a"),
            transcriptURL: sourceURLByRole["transcript"] ?? scratchDirectory.appendingPathComponent("transcript.txt"),
            finalVideoURL: finalVideoURL(slug: project.title, settings: settings, outputFormat: outputFormat),
            outputVideoFormat: outputFormat,
            titleSlug: project.title,
            timelineTrimOffset: CMTime(
                seconds: max(0, project.timelineTrimOffsetSeconds),
                preferredTimescale: 600
            ),
            sourceTimelineOffsets: Dictionary(uniqueKeysWithValues: project.sourceTimelineOffsetSeconds.compactMap {
                key, seconds in
                guard let source = CaptureSource(rawValue: key) else { return nil }
                return (
                    source,
                    CMTime(seconds: max(0, seconds), preferredTimescale: 600)
                )
            })
        )
    }

    func recordingSettings(
        from project: RecordingProject,
        baseSettings: RecordingSettings,
        outputFormat: OutputVideoFormat
    ) -> RecordingSettings {
        var settings = baseSettings
        settings.layout = CaptureLayout(rawValue: project.settings.layout) ?? settings.layout
        settings.outputResolution = OutputResolution(rawValue: project.settings.outputResolution) ?? settings.outputResolution
        settings.outputVideoFormat = outputFormat
        settings.framesPerSecond = RecordingSettings.supportedFrameRates.contains(project.settings.framesPerSecond)
            ? project.settings.framesPerSecond
            : settings.framesPerSecond
        settings.enabledSources = Set(project.settings.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        settings.hiddenSources = Set(project.settings.hiddenSources.compactMap(CaptureSource.init(rawValue:)))
        settings.microphoneGain = clampedGain(project.settings.microphoneGain ?? settings.microphoneGain)
        settings.systemAudioGain = clampedGain(project.settings.systemAudioGain ?? settings.systemAudioGain)
        settings.canvasBackgroundStyle = CanvasBackgroundStyle(rawValue: project.settings.canvasBackgroundStyle) ?? settings.canvasBackgroundStyle
        settings.canvasBackgroundAnimated = project.settings.canvasBackgroundAnimated
        settings.canvasPadding = CGFloat(project.settings.canvasPadding)
        settings.screenCornerRadius = CGFloat(project.settings.screenCornerRadius ?? 0)
        settings.screenShadowEnabled = project.settings.screenShadowEnabled ?? false
        settings.screenContentMode = project.settings.screenContentMode
            .flatMap(CameraContentMode.init(rawValue:)) ?? settings.screenContentMode
        settings.cameraContentMode = CameraContentMode(rawValue: project.settings.cameraContentMode) ?? settings.cameraContentMode
        settings.cameraFramePadding = 0
        settings.cameraShadowEnabled = project.settings.cameraShadowEnabled
        settings.savesSourceFiles = true

        if let firstScene = sceneEvents(from: project).first?.scene {
            settings.sceneLayout = firstScene.sceneLayout
            settings.screenCrop = firstScene.screenSourceGeometry.normalizedCrop
            settings.usesPickedScreenContent = firstScene.screenSourceGeometry.usesPickedContent
            settings.selectedDisplayID = firstScene.screenSourceGeometry.selectedDisplayID
            settings.cameraCropAmount = firstScene.cameraCropAmount
            settings.cameraCropPosition = firstScene.cameraCropPosition
            settings.screenCornerRadius = firstScene.screenCornerRadius
            settings.screenShadowEnabled = firstScene.screenShadowEnabled
            settings.screenContentMode = firstScene.screenContentMode
        }
        return settings
    }

    func sceneEvents(from project: RecordingProject) -> [RecordingSceneEvent] {
        project.sceneEvents.compactMap { event in
            guard let scene = RecordingScene(snapshot: event.scene) else { return nil }
            return RecordingSceneEvent(
                time: event.time,
                scene: scene,
                transition: RecordingSceneTransition(snapshot: event.transition)
            )
        }
    }

    func updateProjectSceneEvent(
        at projectURL: URL,
        eventIndex: Int,
        correction: RecordingProjectSceneCorrection,
        baseSettings: RecordingSettings
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard sceneEvents.indices.contains(eventIndex) else {
            throw RecorderError.mediaWriteFailed("Scene event no longer exists in this project.")
        }

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        let requestedVideoSources = videoSources(for: correction)
        let availableVideoSources = availableRecordedVideoSources(in: project)
        guard requestedVideoSources.isSubset(of: availableVideoSources) else {
            throw RecorderError.mediaWriteFailed("That scene correction requires a source file that is missing from this project.")
        }
        let correctedScene = sceneEvents[eventIndex].scene.corrected(
            correction,
            layout: settings.layout
        )
        sceneEvents[eventIndex] = RecordingSceneEvent(
            time: sceneEvents[eventIndex].time,
            scene: correctedScene,
            transition: sceneEvents[eventIndex].transition
        )
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        baseSettings: RecordingSettings,
        mutate: (inout RecordingScene) -> Void
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard sceneEvents.indices.contains(eventIndex) else {
            throw RecorderError.mediaWriteFailed("Scene event no longer exists in this project.")
        }

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        var scene = sceneEvents[eventIndex].scene
        mutate(&scene)
        sceneEvents[eventIndex] = RecordingSceneEvent(
            time: sceneEvents[eventIndex].time,
            scene: scene,
            transition: sceneEvents[eventIndex].transition
        )
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func insertProjectSceneEvent(
        at projectURL: URL,
        time: Double,
        baseSettings: RecordingSettings
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard !sceneEvents.isEmpty else {
            throw RecorderError.mediaWriteFailed("This project has no scene timeline to split.")
        }
        guard time > 0.05 else {
            throw RecorderError.mediaWriteFailed("Move the playhead past the start before splitting.")
        }
        guard !sceneEvents.contains(where: { abs($0.time - time) < 0.05 }) else {
            throw RecorderError.mediaWriteFailed("A cut already exists at this playhead position.")
        }

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        let sourceIndex = sceneEvents.lastIndex { $0.time < time } ?? 0
        let sourceEvent = sceneEvents[sourceIndex]
        sceneEvents.append(RecordingSceneEvent(time: time, scene: sourceEvent.scene, transition: .cut))
        sceneEvents.sort { $0.time < $1.time }
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func removeProjectSceneEvent(
        at projectURL: URL,
        eventIndex: Int,
        baseSettings: RecordingSettings
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard sceneEvents.indices.contains(eventIndex), eventIndex > 0 else {
            throw RecorderError.mediaWriteFailed("Select a cut after the first segment to remove it.")
        }
        sceneEvents.remove(at: eventIndex)

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func restoreProjectSceneTimeline(
        _ request: RecordingProjectSceneRestoreRequest
    ) throws -> RecordingProject {
        let currentProject = try loadRecordingProject(at: request.projectURL)
        guard currentProject.id == request.snapshot.id else {
            throw RecorderError.mediaWriteFailed("The undo history belongs to another project.")
        }
        let outputFormat = OutputVideoFormat(rawValue: currentProject.settings.outputVideoFormat)
            ?? request.baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: currentProject,
            baseSettings: request.baseSettings,
            outputFormat: outputFormat
        )
        let sceneEvents = sceneEvents(from: request.snapshot)
        guard !sceneEvents.isEmpty else {
            throw RecorderError.mediaWriteFailed("The undo state has no scene timeline.")
        }
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)
        let take = recordingTake(from: currentProject, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: currentProject.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: currentProject.chapters,
            editorTimeline: currentProject.editorTimeline,
            editorState: request.snapshot.editorState
        )
        return try loadRecordingProject(at: request.projectURL)
    }

    func updateProjectEditorState(
        _ request: RecordingProjectEditorStateUpdateRequest
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: request.projectURL)
        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat)
            ?? request.baseSettings.outputVideoFormat
        let settings = recordingSettings(
            from: project,
            baseSettings: request.baseSettings,
            outputFormat: outputFormat
        )
        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents(from: project),
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: request.editorState
        )
        return try loadRecordingProject(at: request.projectURL)
    }

    private func settingsBySyncingEnabledVideoSources(
        _ settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> RecordingSettings {
        let videoSources: Set<CaptureSource> = [.screen, .camera]
        let editedVideoSources = Set(sceneEvents.flatMap(\.scene.enabledSources).filter(videoSources.contains))
        guard !editedVideoSources.isEmpty else { return settings }

        var updated = settings
        let audioSources = updated.enabledSources.subtracting(videoSources)
        updated.enabledSources = audioSources.union(editedVideoSources)
        updated.hiddenSources.subtract(videoSources)
        return updated
    }

    private func availableRecordedVideoSources(in project: RecordingProject) -> Set<CaptureSource> {
        Set(project.sources.compactMap { source in
            guard FileManager.default.fileExists(atPath: source.path),
                  let captureSource = captureSource(forProjectRole: source.role),
                  captureSource == .screen || captureSource == .camera else {
                return nil
            }
            return captureSource
        })
    }

    private func captureSource(forProjectRole role: String) -> CaptureSource? {
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

    private func videoSources(for correction: RecordingProjectSceneCorrection) -> Set<CaptureSource> {
        switch correction {
        case .screenOnly:
            return [.screen]
        case .cameraOnly:
            return [.camera]
        case .screenAndCamera:
            return [.screen, .camera]
        }
    }

    private func clampedGain(_ gain: Double) -> Double {
        min(2.0, max(0.0, gain))
    }

    func projectHistoryURL(for settings: RecordingSettings) -> URL {
        settings.outputDirectory
            .appendingPathComponent("BlitzRecorder Projects", isDirectory: true)
            .appendingPathComponent("projects.json")
    }

    func finalVideoURL(slug: String?, settings: RecordingSettings, outputFormat: OutputVideoFormat) -> URL {
        settings.outputDirectory
            .appendingPathComponent("\(slug ?? "recording")-final.\(outputFormat.fileExtension)")
    }

    func datedSlug(for take: RecordingTake, slug: String) -> String {
        datedSlug(for: take, slug: Optional(slug))
    }

    func datedSlug(for take: RecordingTake, slug: String?) -> String {
        let takeName = take.scratchDirectory.lastPathComponent
        let prefix = String(takeName.prefix(19))
        guard let slug, !slug.isEmpty else {
            return defaultSlug(for: take)
        }
        let slugPrefix = String(slug.prefix(19))
        guard Self.isTakeDatePrefix(prefix),
              !Self.isTakeDatePrefix(slugPrefix) else {
            return slug
        }
        return "\(prefix)-\(slug)"
    }

    func defaultSlug(for take: RecordingTake) -> String {
        Self.defaultSlug(for: take.scratchDirectory)
    }

    func uniqueFileURL(_ url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseName)-\(index).\(pathExtension)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func scratchRoot(for settings: RecordingSettings) -> URL {
        settings.outputDirectory.appendingPathComponent("BlitzRecorder Source Takes", isDirectory: true)
    }

    private func projectID(for take: RecordingTake, projectURL: URL) -> UUID {
        if let data = try? Data(contentsOf: projectURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let existing = try? decoder.decode(RecordingProject.self, from: data) {
                return existing.id
            }
        }
        return UUID()
    }

    private func projectCreatedAt(for take: RecordingTake, fallback: Date) -> Date {
        let prefix = String(take.scratchDirectory.lastPathComponent.prefix(19))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.date(from: prefix) ?? fallback
    }

    private func upsertProjectHistory(_ project: RecordingProject, settings: RecordingSettings) throws {
        var history = loadProjectHistory(settings: settings)
        history.entries.removeAll { $0.id == project.id || $0.projectPath == project.projectPath }
        history.entries.insert(
            RecordingProjectHistory.Entry(
                id: project.id,
                title: project.title,
                projectPath: project.projectPath,
                takeDirectoryPath: project.takeDirectoryPath,
                finalVideoPath: project.finalVideoPath,
                createdAt: project.createdAt,
                updatedAt: project.updatedAt,
                exports: project.exports
            ),
            at: 0
        )
        history.entries.sort { $0.updatedAt > $1.updatedAt }
        try writeProjectHistory(ProjectHistoryWriteRequest(
            history: history,
            settings: settings
        ))
    }

    private func writeProjectHistory(_ request: ProjectHistoryWriteRequest) throws {
        let historyURL = projectHistoryURL(for: request.settings)
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request.history)
        try data.write(to: historyURL, options: .atomic)
    }

    private func sourceFiles(for take: RecordingTake) -> [SourceTakeManifest.SourceFile] {
        [
            ("screen", take.screenURL),
            ("camera", take.cameraURL),
            ("microphone", take.audioURL),
            ("systemAudio", take.systemAudioURL),
            ("transcript", take.transcriptURL)
        ].map { role, url in
            SourceTakeManifest.SourceFile(role: role, path: url.path)
        }
    }

    private func projectSourceFiles(for take: RecordingTake) -> [RecordingProject.SourceFile] {
        [
            ("screen", take.screenURL),
            ("camera", take.cameraURL),
            ("microphone", take.audioURL),
            ("systemAudio", take.systemAudioURL),
            ("transcript", take.transcriptURL)
        ].map { role, url in
            RecordingProject.SourceFile(
                role: role,
                path: url.path,
                exists: FileManager.default.fileExists(atPath: url.path)
            )
        }
    }

    private static func defaultSlug(for scratchDirectory: URL) -> String {
        scratchDirectory.lastPathComponent
    }

    private static func isTakeDatePrefix(_ value: String) -> Bool {
        guard value.count == 19 else { return false }
        let characters = Array(value)
        let digitIndexes: Set<Int> = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        let dashIndexes: Set<Int> = [4, 7, 10, 13, 16]
        for index in characters.indices {
            if digitIndexes.contains(index), !characters[index].isNumber {
                return false
            }
            if dashIndexes.contains(index), characters[index] != "-" {
                return false
            }
        }
        return true
    }

    private func uniqueDirectory(_ url: URL) -> URL {
        var candidate = url
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }
}
