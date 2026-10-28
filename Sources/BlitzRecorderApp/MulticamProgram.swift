import CoreGraphics
import Foundation

/// What a multicam project shows and plays across its timeline: each camera angle with the parts where it is on
/// screen and whether its sound plays, and the shots the number keys cut to. The Cameras inspector, the timeline's
/// camera lanes and the number keys read this one value, so they always agree on which camera is live.
struct MulticamProgram: Equatable {
    struct Angle: Equatable, Identifiable {
        let role: String
        let title: String
        /// The number key that cuts to this camera alone.
        let key: Int
        let syncStatusText: String
        let needsReview: Bool
        /// How many faces the camera usually shows: 1 for a speaker's camera, 2 or more for a wide shot.
        let faceCount: Int
        /// The project's sound comes from this camera; the others stay silent.
        let isSound: Bool
        /// Take seconds where this camera is on screen, in order, touching parts merged.
        let liveRanges: [Range<Double>]

        var id: String { role }

        func isLive(at time: Double) -> Bool {
            liveRanges.contains { $0.contains(time) }
        }
    }

    struct Shot: Equatable, Identifiable {
        let shot: MulticamShot
        let key: Int
        let title: String

        var id: Int { key }
    }

    /// The cameras in the two tiles of a side-by-side part.
    struct Tiles: Equatable {
        let left: String
        let right: String
    }

    struct Request {
        let angles: [CameraAngleRecord]
        /// The camera whose sound plays; nil means Camera 1.
        let soundRole: String?
        /// In take time, sorted, as the editor keeps them.
        let sceneEvents: [RecordingSceneEvent]
        let duration: Double
        let canvas: CaptureLayout
    }

    let angles: [Angle]
    let shots: [Shot]
    private let records: [CameraAngleRecord]
    private let sceneEvents: [RecordingSceneEvent]
    private let canvas: CaptureLayout

    /// Nil for fewer than two camera angles: recorded takes change layouts, not cameras.
    init?(_ request: Request) {
        guard request.angles.count >= 2 else { return nil }
        let roles = Set(request.angles.map(\.role))
        let soundRole = request.soundRole ?? CameraFeeds.mainRole
        records = request.angles
        sceneEvents = request.sceneEvents
        canvas = request.canvas
        shots = MulticamShot.shots(for: request.angles).enumerated().map { index, shot in
            Shot(shot: shot, key: index + 1, title: shot.title(angles: request.angles))
        }
        angles = request.angles.enumerated().map { index, angle in
            Angle(
                role: angle.role, title: angle.title, key: index + 1,
                syncStatusText: angle.syncStatusText, needsReview: angle.needsReview, faceCount: angle.faceCount,
                isSound: angle.role == soundRole,
                liveRanges: Self.liveRanges(.init(
                    role: angle.role, roles: roles, events: request.sceneEvents, duration: request.duration
                ))
            )
        }
    }

    func angle(role: String) -> Angle? {
        angles.first { $0.role == role }
    }

    func shot(key: Int) -> MulticamShot? {
        shots.first { $0.key == key }?.shot
    }

    /// The shot at a playhead time; nil where the part was laid out by hand.
    func liveShot(at time: Double) -> MulticamShot? {
        scene(at: time).flatMap { MulticamShot.current(scene: $0, angles: records) }
    }

    /// How the shot at a playhead time is framed; nil where the part was laid out or cropped by hand.
    func liveFraming(at time: Double) -> MulticamShot.Framing? {
        guard let scene = scene(at: time), let shot = liveShot(at: time) else { return nil }
        return shot.framing(of: scene, .init(angles: records, canvas: canvas))
    }

    /// The framing a cut to a shot gets: the speakers stay as close as they are at the playhead, so they keep their
    /// size from cut to cut. A wide shot or a hand-made part has no closeness to keep.
    func framing(cuttingTo shot: MulticamShot, at time: Double) -> MulticamShot.Framing {
        var framing = MulticamShot.Framing.standard(for: shot)
        guard let live = liveShot(at: time), let current = liveFraming(at: time), framesSpeaker(live) else {
            return framing
        }
        framing.closeness = current.closeness
        if case .sideBySide = live { framing.spacing = current.spacing }
        return framing
    }

    private func framesSpeaker(_ shot: MulticamShot) -> Bool {
        switch shot {
        case .camera(let role): records.record(role: role).map { $0.face != nil && $0.faceCount == 1 } ?? false
        case .sideBySide: true
        }
    }

    /// The camera's face in its picture, origin top left, when it frames one person.
    func face(role: String) -> CGRect? {
        records.record(role: role).flatMap { $0.faceCount == 1 ? $0.face : nil }
    }

    /// The cameras in the two tiles at a playhead time; nil where one camera fills the canvas.
    func tiles(at time: Double) -> Tiles? {
        guard let scene = scene(at: time), scene.sceneLayout.secondCameraFrame != nil else { return nil }
        return Tiles(left: scene.cameraFeeds.camera, right: scene.cameraFeeds.secondCamera)
    }

    private func scene(at time: Double) -> RecordingScene? {
        let index = EditorTimelineIndex.eventIndex(at: time, in: sceneEvents)
        return sceneEvents.indices.contains(index) ? sceneEvents[index].scene : nil
    }

    private struct LiveRangesRequest {
        let role: String
        let roles: Set<String>
        let events: [RecordingSceneEvent]
        let duration: Double
    }

    private static func liveRanges(_ request: LiveRangesRequest) -> [Range<Double>] {
        var ranges: [Range<Double>] = []
        for (index, event) in request.events.enumerated() {
            let start = max(0, event.time)
            let end = index + 1 < request.events.count ? request.events[index + 1].time : request.duration
            guard end > start, shownRoles(.init(scene: event.scene, roles: request.roles)).contains(request.role) else {
                continue
            }
            if let last = ranges.last, abs(last.upperBound - start) < 0.0005 {
                ranges[ranges.count - 1] = last.lowerBound..<end
            } else {
                ranges.append(start..<end)
            }
        }
        return ranges
    }

    private struct ShownRolesRequest {
        let scene: RecordingScene
        let roles: Set<String>
    }

    private static func shownRoles(_ request: ShownRolesRequest) -> Set<String> {
        let scene = request.scene
        guard scene.enabledSources.contains(.camera) else { return [] }
        var shown: Set<String> = [scene.feed(for: .camera, available: request.roles)]
        if scene.sceneLayout.secondCameraFrame != nil {
            shown.insert(scene.feed(for: .secondCamera, available: request.roles))
        }
        return shown
    }
}

extension RecordingProject {
    /// Made from several cameras' files, so the editor cuts between cameras instead of hiding layers.
    var isMulticam: Bool { cameraAngles.count >= 2 }

    /// The editor state playback starts from. A multicam project changes cameras by shot, so its camera layers are
    /// never hidden: a hide saved before that rule would leave a tile black with no lane left to show it again.
    var playbackEditorState: EditorStateSnapshot {
        let state = editorState
        guard isMulticam else { return state }
        let cameraLayers = [SceneLayerKind.camera, .secondCamera].map(\.rawValue)
        return EditorStateSnapshot(
            hiddenVideoSources: state.hiddenVideoSources.filter { !cameraLayers.contains($0) },
            mutedAudioSources: state.mutedAudioSources,
            backgroundMusicPath: state.backgroundMusicPath,
            backgroundMusicBookmarkData: state.backgroundMusicBookmarkData,
            backgroundMusicVolume: state.backgroundMusicVolume,
            exportRecipe: state.exportRecipe,
            audioLevels: state.audioLevels
        )
    }
}
