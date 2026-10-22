import Foundation

struct EditorPlaybackLoadRequest {
    let project: RecordingProject
    let baseSettings: RecordingSettings
    let previewCuts: [TimelineCut]?
}

enum EditorProjectRefreshKind: Equatable {
    case fullPlayback
    case sceneTimeline
}

struct EditorProjectRefreshRequest {
    let hasActivePlayback: Bool
    let isSameProject: Bool
    let hasSameMedia: Bool
}

enum EditorProjectRefreshPolicy {
    static func kind(for request: EditorProjectRefreshRequest) -> EditorProjectRefreshKind {
        guard request.hasActivePlayback,
              request.isSameProject,
              request.hasSameMedia else {
            return .fullPlayback
        }
        return .sceneTimeline
    }
}

enum EditorPlaybackClockSelection {
    static func index(for durations: [Double]) -> Int? {
        guard !durations.isEmpty else { return nil }
        var selectedIndex = 0
        var selectedDuration = normalizedDuration(durations[0])
        for index in durations.indices.dropFirst() {
            let duration = normalizedDuration(durations[index])
            if duration > selectedDuration {
                selectedIndex = index
                selectedDuration = duration
            }
        }
        return selectedIndex
    }

    private static func normalizedDuration(_ duration: Double) -> Double {
        duration.isFinite ? max(0, duration) : 0
    }
}

enum EditorPlaybackClockPublish {
    struct Tick: Equatable {
        let nextTime: Double
        let currentTime: Double
        let nextIsPlaying: Bool
        let isPlaying: Bool
        let isSameSceneSegment: Bool
    }

    struct Update: Equatable {
        var currentTime: Double?
        var isPlaying: Bool?
        var shouldRefreshSceneCache: Bool
    }

    static func apply(_ tick: Tick) -> Update {
        var update = Update(currentTime: nil, isPlaying: nil, shouldRefreshSceneCache: false)
        if tick.nextIsPlaying != tick.isPlaying {
            update.isPlaying = tick.nextIsPlaying
        }
        if tick.nextIsPlaying {
            if !tick.isSameSceneSegment {
                update.currentTime = tick.nextTime
                update.shouldRefreshSceneCache = true
            }
        } else if abs(tick.nextTime - tick.currentTime) > 0.0001 {
            update.currentTime = tick.nextTime
        }
        return update
    }
}

enum EditorPlaybackRate: Float, CaseIterable, Equatable {
    case half = 0.5
    case normal = 1
    case oneAndAHalf = 1.5
    case double = 2
    case twoAndAHalf = 2.5

    var displayName: String {
        switch self {
        case .half:
            "0.5×"
        case .normal:
            "1×"
        case .oneAndAHalf:
            "1.5×"
        case .double:
            "2×"
        case .twoAndAHalf:
            "2.5×"
        }
    }

    var nextFaster: EditorPlaybackRate {
        switch self {
        case .half:
            .normal
        case .normal:
            .oneAndAHalf
        case .oneAndAHalf:
            .double
        case .double, .twoAndAHalf:
            .twoAndAHalf
        }
    }
}


struct EditorPlaybackSceneTimelineUpdate {
    let project: RecordingProject
    let baseSettings: RecordingSettings
    let preservesPreviewSceneOverride: Bool
}

struct EditorPlaybackMediaSignature: Equatable {
    let version: Int
    let id: UUID
    let projectPath: String
    let takeDirectoryPath: String
    let finalVideoPath: String?
    let timelineTrimOffsetSeconds: Double
    let sourceTimelineOffsetSeconds: [String: Double]
    let settings: RecordingProject.SettingsSnapshot
    let sources: [RecordingProject.SourceFile]
    let cuts: [TimelineCut]

    init(project: RecordingProject) {
        version = project.version
        id = project.id
        projectPath = project.projectPath
        takeDirectoryPath = project.takeDirectoryPath
        finalVideoPath = project.finalVideoPath
        timelineTrimOffsetSeconds = project.timelineTrimOffsetSeconds
        sourceTimelineOffsetSeconds = project.sourceTimelineOffsetSeconds
        settings = project.settings
        sources = project.sources
        cuts = project.edits.enabledCuts
    }
}

extension EditorPlaybackController {
    struct AudioReload {
        let project: RecordingProject
        let baseSettings: RecordingSettings
    }

    struct AudioReloadWork {
        let request: AudioReload
        let settings: RecordingSettings
        let outputFormat: OutputVideoFormat
        let timeMap: TimelineTimeMap
        let cleanup: VoiceCleanupSettings
        let requestID: Int
        let generation: Int
    }

    struct AudioInstall {
        let audio: Merger.EditorPlaybackAudio
        let cleanup: VoiceCleanupSettings
        let requestID: Int
        let generation: Int
    }
}
