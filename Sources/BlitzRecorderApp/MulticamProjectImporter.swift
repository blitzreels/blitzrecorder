import AVFoundation
import CoreGraphics
import Foundation

/// Turns files shot at the same time on several devices (a wide shot and one close-up per speaker) into one
/// project. Their sound places them on one timeline, the clearest sound becomes the program audio, and the
/// speakers open side by side, each framed on their face. Files are referenced where they are, never copied.
struct MulticamProjectImporter {
    struct Request {
        let urls: [URL]
        let settings: RecordingSettings
        let onProgress: @Sendable (VideoProjectImporter.Progress) async -> Void
    }

    /// The project, when at least two files share their sound, and the files that matched none (they import on
    /// their own).
    struct Result {
        let project: RecordingProject?
        let unmatched: [URL]
    }

    /// A placement this unsure still joins the project, marked "Check sync"; below it the file is another shoot.
    static let minimumJoinConfidence = 0.5

    private struct Angle {
        let url: URL
        let probe: VideoProjectImporter.Probe
        let onsets: AngleAudioSync.Onsets
        /// Seconds into the reference where this file starts; 0 for the reference itself.
        var offset: Double = 0
        var placement: AngleAudioSync.Placement?
        var faces = CameraAngleFraming.Faces(face: nil, count: 0, yaw: nil)
    }

    func importShoot(_ request: Request) async throws -> Result {
        let access = request.urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { for (url, started) in access where started { url.stopAccessingSecurityScopedResource() } }
        var heard: [Angle] = []
        var unmatched: [URL] = []
        for (index, url) in request.urls.enumerated() {
            try Task.checkCancellation()
            await request.onProgress(.init(filename: url.lastPathComponent, stage: "Listening to sound",
                                           fraction: Double(index) / Double(request.urls.count)))
            guard let probe = try? await VideoProjectImporter.probe(url), probe.hasAudio,
                  let onsets = try? await AngleAudioSync.onsets(url: url) else {
                unmatched.append(url)
                continue
            }
            heard.append(Angle(url: url, probe: probe, onsets: onsets))
        }
        guard let referenceIndex = heard.indices.max(by: { heard[$0].onsets.speechLevel < heard[$1].onsets.speechLevel })
        else { return Result(project: nil, unmatched: request.urls) }
        let reference = heard[referenceIndex]
        var angles = [reference]
        for (index, angle) in heard.enumerated() where index != referenceIndex {
            await request.onProgress(.init(filename: angle.url.lastPathComponent, stage: "Syncing by sound", fraction: nil))
            guard let placement = AngleAudioSync.place(.init(reference: reference.onsets, other: angle.onsets)),
                  placement.confidence >= Self.minimumJoinConfidence else {
                unmatched.append(angle.url)
                continue
            }
            var placed = angle
            placed.offset = placement.offset
            placed.placement = placement
            angles.append(placed)
        }
        guard angles.count >= 2 else { return Result(project: nil, unmatched: request.urls) }
        for index in angles.indices {
            try Task.checkCancellation()
            await request.onProgress(.init(filename: angles[index].url.lastPathComponent, stage: "Finding faces",
                                           fraction: Double(index) / Double(angles.count)))
            angles[index].faces = await CameraAngleFraming.faces(url: angles[index].url)
        }
        let project = try await writeProject(.init(angles: angles, programAudio: reference.url, request: request))
        return Result(project: project, unmatched: unmatched)
    }

    private struct ProjectRequest {
        let angles: [Angle]
        let programAudio: URL
        let request: Request
    }

    private func writeProject(_ build: ProjectRequest) async throws -> RecordingProject {
        let ordered = Self.roles(for: build.angles)
        let main = ordered[0].angle
        // Camera 1 sets the timeline: every other angle is placed relative to where it starts.
        let placed = ordered.map { entry in (role: entry.role, angle: entry.angle, offset: entry.angle.offset - main.offset) }
        var settings = VideoProjectImporter.importSettings(.init(probe: main.probe, base: build.request.settings))
        settings.enabledSources = [.camera, .microphone]
        let libraryAccess = OutputDirectoryAccess(locations: [settings.sourceStorage])
        defer { libraryAccess.stop() }
        guard libraryAccess.hasSecurityScopedAccess else {
            throw RecorderError.outputDirectoryUnavailable(TakeFileStore.permissionRecoveryMessage(for: settings.sourceStorage.url))
        }
        let store = TakeFileStore()
        let directory = store.scratchRoot(for: settings).appendingPathComponent("Import-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }

        var sources: [RecordingProject.SourceFile] = []
        for entry in placed {
            let bookmark = try entry.angle.url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            var source = RecordingProject.SourceFile(role: entry.role, path: entry.angle.url.path, exists: true,
                                                     bookmarkData: bookmark)
            source.resolveExternalReference()
            sources.append(source)
        }
        let program = placed.first { $0.angle.url == build.programAudio } ?? placed[0]
        let audioURL = Self.soundURL(directory: directory, role: program.role)
        let programName = program.angle.url.lastPathComponent
        await build.request.onProgress(.init(filename: programName, stage: "Preparing audio", fraction: nil))
        try await VideoProjectImporter.extractAudio(.init(
            asset: AVURLAsset(url: program.angle.url), destination: audioURL, tracks: .first,
            skippedSeconds: max(0, -program.offset), onFraction: { fraction in
                await build.request.onProgress(.init(filename: programName, stage: "Preparing audio", fraction: fraction))
            }
        ))
        try Task.checkCancellation()
        await build.request.onProgress(.init(filename: main.url.lastPathComponent, stage: "Creating project", fraction: nil))
        let title = Self.projectTitle(for: placed.map(\.angle.url))
        let metadata = VideoProjectImporter.Metadata(
            originalFilename: main.url.lastPathComponent, initialTitle: title, width: main.probe.width,
            height: main.probe.height, framesPerSecond: main.probe.framesPerSecond, duration: main.probe.duration
        )
        try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("import.json"), options: .atomic)

        let records = placed.map { entry in
            CameraAngleRecord(
                role: entry.role,
                title: Self.angleTitle(.init(url: entry.angle.url, role: entry.role, faces: entry.angle.faces, ordered: ordered)),
                offsetSeconds: entry.offset,
                method: entry.angle.placement == nil ? .reference : .audio,
                confidence: entry.angle.placement?.confidence ?? 1,
                drift: entry.angle.placement?.drift ?? 0,
                face: entry.angle.faces.face,
                faceCount: entry.angle.faces.count,
                aspectRatio: entry.angle.probe.width / entry.angle.probe.height
            )
        }
        let opening = Self.openingScenes(.init(settings: settings, records: records))
        settings = opening.settings

        let take = RecordingTake(
            scratchDirectory: directory, screenURL: directory.appendingPathComponent("screen.mov"),
            cameraURL: main.url, audioURL: audioURL, systemAudioURL: directory.appendingPathComponent("system-audio.m4a"),
            transcriptURL: directory.appendingPathComponent("transcript.txt"),
            finalVideoURL: store.finalVideoURL(slug: title, settings: settings, outputFormat: .mp4),
            outputVideoFormat: .mp4, titleSlug: title,
            sourceTimelineOffsets: [.microphone: CMTime(seconds: max(0, program.offset), preferredTimescale: 600)],
            sourceReferences: sources,
            cameraAngleFiles: placed.dropFirst().map { SourceTrackFile(role: $0.role, url: $0.angle.url) },
            cameraAngles: records,
            programAudioRole: program.role
        )
        try store.writeSourceTakeManifest(for: take, settings: settings, finalVideoURL: nil)
        try store.writeRecordingProject(for: take, settings: settings,
                                        sceneEvents: opening.events,
                                        finalVideoURL: nil)
        let project = try store.loadRecordingProject(at: take.projectURL)
        completed = true
        return project
    }

    /// Where an angle's sound is kept once extracted, in the project folder.
    static func soundURL(directory: URL, role: String) -> URL {
        directory.appendingPathComponent("sound-\(role).m4a")
    }

    // MARK: Roles and names

    /// Camera 1 is the wide shot (the angle showing most faces); speakers follow, the one looking toward the
    /// picture's right first, since they sit on the left; then any other angle.
    private static func roles(for angles: [Angle]) -> [(role: String, angle: Angle)] {
        let main = angles.max { lhs, rhs in
            lhs.faces.count != rhs.faces.count ? lhs.faces.count < rhs.faces.count : lhs.offset > rhs.offset
        } ?? angles[0]
        let others = angles.filter { $0.url != main.url }
        let speakers = others.filter { $0.faces.count == 1 }.sorted { ($0.faces.yaw ?? 0) > ($1.faces.yaw ?? 0) }
        let rest = others.filter { $0.faces.count != 1 }
        let tracks = NumberedSourceTracks.cameraAngles
        return [(CameraFeeds.mainRole, main)]
            + (speakers + rest).enumerated().map { (tracks.role(number: $0.offset + tracks.firstNumber), $0.element) }
    }

    private struct TitleRequest {
        let url: URL
        let role: String
        let faces: CameraAngleFraming.Faces
        let ordered: [(role: String, angle: Angle)]
    }

    /// The file's own name when someone chose it; otherwise what the angle shows.
    private static func angleTitle(_ request: TitleRequest) -> String {
        let stem = request.url.deletingPathExtension().lastPathComponent
        if !isCameraDefaultName(stem) { return stem }
        if request.role == CameraFeeds.mainRole { return request.faces.count >= 2 ? "Wide shot" : "Camera 1" }
        let speakers = request.ordered.filter { $0.role != CameraFeeds.mainRole && $0.angle.faces.count == 1 }
        if speakers.count == 2, let index = speakers.firstIndex(where: { $0.role == request.role }) {
            return index == 0 ? "Left speaker" : "Right speaker"
        }
        return NumberedSourceTracks.cameraAngles.number(role: request.role)
            .map(NumberedSourceTracks.cameraAngles.displayName(number:)) ?? stem
    }

    /// Names cameras give files on their own: IMG_7573, DJI_20261027174624_0094_D, GX010042, C0001, MVI_0001.
    static func isCameraDefaultName(_ stem: String) -> Bool {
        stem.range(of: #"^(IMG|DJI|MVI|VID|PXL|GX|GH|GOPR|DSC|C)[_\-]?\d"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The folder the files share, when they were gathered in one; otherwise the wide shot's name.
    static func projectTitle(for urls: [URL]) -> String {
        let folders = Set(urls.map { $0.deletingLastPathComponent().path })
        if folders.count == 1, let folder = urls.first?.deletingLastPathComponent().lastPathComponent,
           !folder.isEmpty, !["Downloads", "Desktop", "Movies", "DCIM"].contains(folder) {
            return folder
        }
        let stem = urls.first?.deletingPathExtension().lastPathComponent ?? ""
        return stem.isEmpty ? "Multicam video" : stem
    }

    // MARK: Opening scenes

    struct OpeningSceneRequest {
        let settings: RecordingSettings
        let records: [CameraAngleRecord]
    }

    struct OpeningScenes {
        /// The project's settings: the first scene, the wide shot on the whole canvas.
        let settings: RecordingSettings
        let events: [RecordingSceneEvent]
    }

    /// The wide shot, then the two framed speakers side by side from the moment both their cameras roll. A shoot
    /// without two framed speakers stays on the wide shot.
    static func openingScenes(_ request: OpeningSceneRequest) -> OpeningScenes {
        var wide = request.settings
        wide.sceneLayout = SceneLayout()
        wide.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        wide.cameraFeeds = .main
        wide.selectedScenePreset = .webcamFullscreen
        wide.cameraContentMode = .fit
        let opening = RecordingScene(settings: wide)
        guard let speakers = MulticamShot.speakers(in: request.records) else {
            return OpeningScenes(settings: wide, events: [.init(time: 0, scene: opening)])
        }
        var sideBySide = opening
        MulticamShot.sideBySide(left: speakers.left, right: speakers.right)
            .apply(to: &sideBySide, .init(angles: request.records, canvas: request.settings.layout))
        let starts = [speakers.left, speakers.right].compactMap { request.records.record(role: $0)?.offsetSeconds }
        // Whole frames, so the cut lands on the first frame both speakers are on camera.
        let bothRolling = (max(0, starts.max() ?? 0) * 30).rounded(.up) / 30
        guard bothRolling > 0.05 else { return OpeningScenes(settings: wide, events: [.init(time: 0, scene: sideBySide)]) }
        return OpeningScenes(settings: wide, events: [.init(time: 0, scene: opening), .init(time: bothRolling, scene: sideBySide)])
    }
}
