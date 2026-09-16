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

        var rect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    struct PointValue: Codable, Equatable {
        let x: Double
        let y: Double

        init(_ point: CGPoint) {
            self.x = Double(point.x)
            self.y = Double(point.y)
        }

        var point: CGPoint {
            CGPoint(x: x, y: y)
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

    struct CutSnapshot: Codable, Equatable, Identifiable {
        let id: UUID
        let start: Double
        let end: Double
        let kind: String
        let source: String
        let enabled: Bool

        init(_ cut: TimelineCut) {
            id = cut.id
            start = cut.start
            end = cut.end
            kind = cut.kind.rawValue
            source = cut.source.rawValue
            enabled = cut.isEnabled
        }

        var cut: TimelineCut {
            TimelineCut(
                id: id,
                start: start,
                end: end,
                kind: TimelineCutKind(rawValue: kind) ?? .manual,
                source: TimelineCutSource(rawValue: source) ?? .user,
                isEnabled: enabled
            )
        }
    }

    struct TextOverlayStyleSnapshot: Codable, Equatable {
        let preset: String
        let size: Double
        let weight: String
        let color: String
        let background: String
        let alignment: String

        init(_ style: TextOverlayStyle) {
            preset = style.preset.rawValue
            size = style.size
            weight = style.weight.rawValue
            color = style.colorHex
            background = style.background.rawValue
            alignment = style.alignment.rawValue
        }

        var style: TextOverlayStyle {
            let resolvedPreset = TextOverlayPreset(rawValue: preset) ?? .caption
            let base = TextOverlayStyle.preset(resolvedPreset)
            return TextOverlayStyle(
                preset: resolvedPreset,
                size: size,
                weight: TextOverlayWeight(rawValue: weight) ?? base.weight,
                colorHex: color,
                background: TextOverlayBackground(rawValue: background) ?? base.background,
                alignment: TextOverlayAlignment(rawValue: alignment) ?? base.alignment
            )
        }
    }

    struct TextOverlaySnapshot: Codable, Equatable, Identifiable {
        let id: UUID
        let start: Double
        let end: Double
        let text: String
        let frame: RectValue
        let style: TextOverlayStyleSnapshot
        let fadeSeconds: Double

        init(_ overlay: TextOverlay) {
            id = overlay.id
            start = overlay.start
            end = overlay.end
            text = overlay.text
            frame = RectValue(overlay.frame)
            style = TextOverlayStyleSnapshot(overlay.style)
            fadeSeconds = overlay.fadeSeconds
        }

        var overlay: TextOverlay {
            TextOverlay(
                id: id,
                start: start,
                end: end,
                text: text,
                frame: frame.rect,
                style: style.style,
                fadeSeconds: fadeSeconds
            )
        }
    }

    struct ZoomTrackSnapshot: Codable, Equatable {
        struct Keyframe: Codable, Equatable, Identifiable {
            let id: UUID
            let time: Double
            let amount: Double
            let position: PointValue
            let easing: String

            init(_ keyframe: ScreenZoomKeyframe) {
                id = keyframe.id
                time = keyframe.time
                amount = keyframe.amount
                position = PointValue(keyframe.position)
                easing = keyframe.easing.rawValue
            }

            var keyframe: ScreenZoomKeyframe {
                ScreenZoomKeyframe(
                    id: id,
                    time: time,
                    amount: amount,
                    position: position.point,
                    easing: ScreenZoomEasing(rawValue: easing) ?? .easeInOut
                )
            }
        }

        let keyframes: [Keyframe]
        let generatedFromCursor: Bool
        let intensity: Double
        let isEnabled: Bool

        static let empty = ZoomTrackSnapshot(keyframes: [], generatedFromCursor: false, intensity: 2)

        init(keyframes: [Keyframe], generatedFromCursor: Bool, intensity: Double) {
            self.keyframes = keyframes
            self.generatedFromCursor = generatedFromCursor
            self.intensity = intensity
            self.isEnabled = true
        }

        init(_ track: ScreenZoomTrack) {
            keyframes = track.keyframes.map(Keyframe.init)
            generatedFromCursor = track.generatedFromCursor
            intensity = track.intensity
            isEnabled = track.isEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keyframes = try container.decode([Keyframe].self, forKey: .keyframes)
            generatedFromCursor = try container.decode(Bool.self, forKey: .generatedFromCursor)
            intensity = try container.decode(Double.self, forKey: .intensity)
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        }

        var track: ScreenZoomTrack {
            var track = ScreenZoomTrack(
                keyframes: keyframes.map(\.keyframe),
                generatedFromCursor: generatedFromCursor,
                intensity: intensity
            )
            track.isEnabled = isEnabled
            return track
        }
    }

    struct TimelineEditsSnapshot: Codable, Equatable {
        let cuts: [CutSnapshot]
        let textOverlays: [TextOverlaySnapshot]
        let zoom: ZoomTrackSnapshot
        let videoSplits: [Double]
        let silenceRemovalApplied: Bool
        let silenceOverrides: [SilenceOverride]
        let cursorStyle: CursorPresentationStyle
        let voiceCleanup: VoiceCleanupSettings
        let outputVariants: [RecordingOutputVariant]
        let activeOutputLayout: CaptureLayout?
        let privacyMasks: [PrivacyMask]
        let cameraFollowsZoom: Bool

        static let empty = TimelineEditsSnapshot(cuts: [], textOverlays: [], zoom: .empty)

        init(cuts: [CutSnapshot], textOverlays: [TextOverlaySnapshot], zoom: ZoomTrackSnapshot) {
            self.cuts = cuts
            self.textOverlays = textOverlays
            self.zoom = zoom
            self.videoSplits = []
            self.silenceRemovalApplied = false
            self.silenceOverrides = []
            self.cursorStyle = .standard
            self.cameraFollowsZoom = false
            self.privacyMasks = []
            self.outputVariants = []
            self.voiceCleanup = .disabled
            self.activeOutputLayout = nil
        }

        init(_ edits: TimelineEdits) {
            cuts = edits.cuts.map(CutSnapshot.init)
            textOverlays = edits.textOverlays.map(TextOverlaySnapshot.init)
            zoom = ZoomTrackSnapshot(edits.zoom)
            videoSplits = edits.videoSplits
            silenceRemovalApplied = edits.silenceRemovalApplied
            silenceOverrides = edits.silenceOverrides
            cursorStyle = edits.cursorStyle
            cameraFollowsZoom = edits.cameraFollowsZoom
            privacyMasks = edits.privacyMasks
            outputVariants = edits.outputVariants
            voiceCleanup = edits.voiceCleanup
            activeOutputLayout = edits.activeOutputLayout
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cuts = try container.decodeIfPresent([CutSnapshot].self, forKey: .cuts) ?? []
            textOverlays = try container.decodeIfPresent([TextOverlaySnapshot].self, forKey: .textOverlays) ?? []
            zoom = try container.decodeIfPresent(ZoomTrackSnapshot.self, forKey: .zoom) ?? .empty
            videoSplits = try container.decodeIfPresent([Double].self, forKey: .videoSplits) ?? []
            silenceRemovalApplied = try container.decodeIfPresent(Bool.self, forKey: .silenceRemovalApplied)
                ?? cuts.contains { $0.cut.kind == .silence && $0.cut.isEnabled }
            silenceOverrides = try container.decodeIfPresent([SilenceOverride].self, forKey: .silenceOverrides) ?? []
            cursorStyle = try container.decodeIfPresent(CursorPresentationStyle.self, forKey: .cursorStyle) ?? .standard
            voiceCleanup = try container.decodeIfPresent(VoiceCleanupSettings.self, forKey: .voiceCleanup) ?? .disabled
            outputVariants = try container.decodeIfPresent([RecordingOutputVariant].self, forKey: .outputVariants) ?? []
            activeOutputLayout = try container.decodeIfPresent(CaptureLayout.self, forKey: .activeOutputLayout)
            privacyMasks = try container.decodeIfPresent([PrivacyMask].self, forKey: .privacyMasks) ?? []
            cameraFollowsZoom = try container.decodeIfPresent(Bool.self, forKey: .cameraFollowsZoom) ?? false
        }

        var edits: TimelineEdits {
            TimelineEdits(
                cuts: cuts.map(\.cut),
                textOverlays: textOverlays.map(\.overlay),
                zoom: zoom.track,
                silenceOverrides: silenceOverrides,
                cursorStyle: cursorStyle,
                cameraFollowsZoom: cameraFollowsZoom,
                privacyMasks: privacyMasks,
                outputVariants: outputVariants,
                activeOutputLayout: activeOutputLayout,
                voiceCleanup: voiceCleanup,
                videoSplits: videoSplits,
                silenceRemovalApplied: silenceRemovalApplied
            )
        }

        var isEmpty: Bool {
            videoSplits.isEmpty && !silenceRemovalApplied && cuts.isEmpty && textOverlays.isEmpty && zoom.keyframes.isEmpty && silenceOverrides.isEmpty
                && cursorStyle == .standard && !cameraFollowsZoom && privacyMasks.isEmpty && outputVariants.isEmpty && activeOutputLayout == nil && voiceCleanup == .disabled
        }
    }

    struct AnalysisSnapshot: Codable, Equatable {
        let cursorTrackPath: String?
        let silenceAnalysisPath: String?

        static let empty = AnalysisSnapshot(cursorTrackPath: nil, silenceAnalysisPath: nil)

        init(cursorTrackPath: String?, silenceAnalysisPath: String?) {
            self.cursorTrackPath = cursorTrackPath
            self.silenceAnalysisPath = silenceAnalysisPath
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cursorTrackPath = try container.decodeIfPresent(String.self, forKey: .cursorTrackPath)
            silenceAnalysisPath = try container.decodeIfPresent(String.self, forKey: .silenceAnalysisPath)
        }

        var isEmpty: Bool {
            cursorTrackPath == nil && silenceAnalysisPath == nil
        }
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
    }

    var edits: TimelineEdits {
        timelineEdits.edits
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
    var recordedAt: Date {
        createdAt
            ?? RecordingProjectDisplayTitle.timestampDate(from: title)
            ?? RecordingProjectDisplayTitle.timestampDate(
                from: URL(fileURLWithPath: takeDirectoryPath).lastPathComponent
            )
            ?? updatedAt
    }

    var displayTitle: String {
        RecordingProjectDisplayTitle.make(rawTitle: title, createdAt: recordedAt)
    }
}

extension RecordingProjectHistory {
    mutating func sortByRecordedDate() {
        entries.sort { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt {
                return lhs.recordedAt > rhs.recordedAt
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
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

struct RecordingProjectTrashReceipt: Equatable {
    let project: RecordingProjectHistory.Entry
    let trashedDirectory: URL
}

struct RecordingProjectRestorationRequest {
    let receipt: RecordingProjectTrashReceipt
    let settings: RecordingSettings
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

struct RecordingProjectTimelineEditsUpdateRequest {
    let projectURL: URL
    let edits: TimelineEdits
    let baseSettings: RecordingSettings
}

struct RecordingProjectAnalysisUpdateRequest {
    let projectURL: URL
    let analysis: RecordingProject.AnalysisSnapshot
    let baseSettings: RecordingSettings
}

struct ProjectHistoryWriteRequest {
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
            return BlitzSymbols.screen
        case .cameraOnly:
            return BlitzSymbols.camera
        case .screenAndCamera:
            return BlitzSymbols.pictureInPicture
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

extension RecordingSceneTransition {
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
