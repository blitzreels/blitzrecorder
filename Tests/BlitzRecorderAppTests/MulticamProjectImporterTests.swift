import AVFoundation
import CoreGraphics
import Vision
import XCTest
@testable import BlitzRecorderApp

final class MulticamProjectImporterTests: XCTestCase {
    func testCropPutsACentredFaceInTheMiddleAtTheAskedSize() {
        let crop = CameraAngleFraming.crop(.init(
            face: CGRect(x: 0.45, y: 0.4, width: 0.1, height: 0.2),
            sourceAspectRatio: 16.0 / 9.0, tileAspectRatio: 0.9, faceHeight: 0.25, eyeLine: 0.5
        ))
        XCTAssertEqual(crop.amount.x, 0.2, accuracy: 0.0001, "a face 0.2 tall at 0.25 of the tile needs 0.8 of the height")
        XCTAssertEqual(crop.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(crop.position.y, 0, accuracy: 0.0001)
    }

    func testCropFollowsAFaceToTheRightAndNearTheTop() {
        let crop = CameraAngleFraming.crop(.init(
            face: CGRect(x: 0.7, y: 0.1, width: 0.1, height: 0.15),
            sourceAspectRatio: 16.0 / 9.0, tileAspectRatio: 0.9, faceHeight: 0.25, eyeLine: 0.42
        ))
        XCTAssertGreaterThan(crop.position.x, 0.4)
        XCTAssertGreaterThan(crop.position.y, 0, "y counts up from the bottom, so a face near the top moves the crop up")
        let rect = SourceCropGeometry.cropRectangle(
            source: CGRect(x: 0, y: 0, width: 16.0 / 9.0, height: 1), target: CGRect(x: 0, y: 0, width: 0.9, height: 1),
            sourceCropAmount: crop.amount, sourceCropPosition: crop.position
        )
        XCTAssertEqual(rect.height, 0.6, accuracy: 0.0001)
        XCTAssertEqual(rect.midX, 0.75 * 16.0 / 9.0, accuracy: 0.0001)
    }

    func testCameraNamesAreReplacedButChosenNamesKept() {
        for stem in ["IMG_7573", "DJI_20261027174624_0094_D", "GX010042", "C0001", "MVI_0420", "PXL_20261027"] {
            XCTAssertTrue(MulticamProjectImporter.isCameraDefaultName(stem), stem)
        }
        for stem in ["plan-emmanuel", "wide-shot", "Interview Thomas", "Camera A"] {
            XCTAssertFalse(MulticamProjectImporter.isCameraDefaultName(stem), stem)
        }
    }

    func testProjectIsNamedAfterTheFolderTheFilesShare() {
        let folder = URL(fileURLWithPath: "/Volumes/Shoot/uneed-podcast-1")
        XCTAssertEqual(MulticamProjectImporter.projectTitle(for: [
            folder.appendingPathComponent("a.MOV"), folder.appendingPathComponent("b.MP4")
        ]), "uneed-podcast-1")
        XCTAssertEqual(MulticamProjectImporter.projectTitle(for: [
            URL(fileURLWithPath: "/Users/me/Downloads/IMG_1.MOV"), URL(fileURLWithPath: "/Users/me/Downloads/IMG_2.MOV")
        ]), "IMG_1")
    }

    func testAngleRecordsRoundTripThroughTheProjectFile() throws {
        let record = CameraAngleRecord(role: "camera-2", title: "Left speaker", offsetSeconds: -1.5, method: .audio,
                                       confidence: 0.93, drift: 0.00001, face: CGRect(x: 0.4, y: 0.3, width: 0.1, height: 0.2),
                                       faceCount: 1, aspectRatio: 16.0 / 9.0)
        let data = try JSONEncoder().encode([record])
        XCTAssertEqual(try JSONDecoder().decode([CameraAngleRecord].self, from: data), [record])
        XCTAssertEqual(record.syncStatusText, "Synced by audio · 93 %")
        var unsure = record
        unsure.confidence = 0.6
        XCTAssertEqual(unsure.syncStatusText, "Check sync")
        unsure.drift = 0.001
        XCTAssertEqual(unsure.syncStatusText, "Check sync · speeds differ")
    }

    private var podcastAngles: [CameraAngleRecord] {
        [
            CameraAngleRecord(role: "camera", title: "wide-shot", offsetSeconds: 0, method: .audio, confidence: 1, drift: 0,
                              face: nil, faceCount: 2, aspectRatio: 16.0 / 9.0),
            CameraAngleRecord(role: "camera-2", title: "plan-emmanuel", offsetSeconds: 18.1, method: .reference,
                              confidence: 1, drift: 0, face: CGRect(x: 0.47, y: 0.33, width: 0.08, height: 0.15),
                              faceCount: 1, aspectRatio: 16.0 / 9.0),
            CameraAngleRecord(role: "camera-3", title: "plan-thomas", offsetSeconds: 72.36, method: .audio, confidence: 1,
                              drift: 0, face: CGRect(x: 0.45, y: 0.26, width: 0.08, height: 0.15), faceCount: 1,
                              aspectRatio: 16.0 / 9.0)
        ]
    }

    func testShotsAreEachCameraThenTheSpeakersSideBySide() throws {
        let angles = podcastAngles
        let shots = MulticamShot.shots(for: angles)
        XCTAssertEqual(shots, [.camera(role: "camera"), .camera(role: "camera-2"), .camera(role: "camera-3"),
                               .sideBySide(left: "camera-2", right: "camera-3")])
        XCTAssertEqual(shots.map { $0.title(angles: angles) }, ["wide-shot", "plan-emmanuel", "plan-thomas", "Side by side"])

        var scene = RecordingScene(settings: RecordingSettings())
        shots[3].apply(to: &scene, .init(angles: angles, canvas: .horizontal))
        XCTAssertEqual(scene.cameraFeeds, CameraFeeds(camera: "camera-2", secondCamera: "camera-3"))
        let left = scene.sceneLayout.cameraFrame, right = try XCTUnwrap(scene.sceneLayout.secondCameraFrame)
        XCTAssertLessThan(left.maxX, right.minX, "left and right, never stacked")
        XCTAssertEqual(left.height, right.height, accuracy: 0.0001)
        XCTAssertGreaterThan(scene.cameraCropAmount.x, 0, "each tile is cropped in on its speaker's face")
        XCTAssertGreaterThan(scene.secondCameraCropAmount.x, 0)
        XCTAssertFalse(scene.enabledSources.contains(.screen))
        XCTAssertEqual(MulticamShot.current(scene: scene, angles: angles), shots[3])

        shots[2].apply(to: &scene, .init(angles: angles, canvas: .horizontal))
        XCTAssertNil(scene.sceneLayout.secondCameraFrame)
        XCTAssertEqual(scene.sceneLayout.cameraFrame, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(scene.cameraFeeds.camera, "camera-3")
        XCTAssertEqual(scene.cameraCropAmount, .zero, "a camera on the whole canvas shows its whole picture")
        XCTAssertEqual(MulticamShot.current(scene: scene, angles: angles), shots[2])
    }

    func testNumberKeysCutToCameraShots() {
        for number in 1...9 {
            XCTAssertEqual(EditorKeyboardCommand.resolve(.init(keyCode: 0, characters: "\(number)", modifiers: [])),
                           .cameraShot(number))
        }
        XCTAssertNil(EditorKeyboardCommand.resolve(.init(keyCode: 0, characters: "1", modifiers: [.option])))
        XCTAssertNil(EditorKeyboardCommand.resolve(.init(keyCode: 0, characters: "0", modifiers: [])))
        XCTAssertEqual(EditorKeyboardDispatch.action(.command(.cameraShot(3)), zoom: 1, duration: 60), .cameraShot(3))
    }

    /// Every path that rewrites a saved project keeps where the sync put each angle: editor saves (and reads while
    /// one is queued), renames and finished exports.
    func testEditorSavesRenamesAndExportsKeepTheAngles() throws {
        let fixture = try SyntheticRecording()
        let store = TakeFileStore()
        let directory = fixture.root.appendingPathComponent("Multicam", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let angles = [
            CameraAngleRecord(role: "camera", title: "Wide shot", offsetSeconds: 0, method: .audio, confidence: 1,
                              drift: 0, face: nil, faceCount: 2, aspectRatio: 16.0 / 9.0),
            CameraAngleRecord(role: "camera-2", title: "Left speaker", offsetSeconds: 18.1, method: .reference,
                              confidence: 1, drift: 0, face: CGRect(x: 0.45, y: 0.3, width: 0.08, height: 0.15), faceCount: 1,
                              aspectRatio: 16.0 / 9.0)
        ]
        let take = RecordingTake(
            scratchDirectory: directory, screenURL: directory.appendingPathComponent("screen.mov"),
            cameraURL: directory.appendingPathComponent("camera.mov"), audioURL: directory.appendingPathComponent("audio.m4a"),
            systemAudioURL: directory.appendingPathComponent("system-audio.m4a"),
            transcriptURL: directory.appendingPathComponent("transcript.txt"),
            finalVideoURL: directory.appendingPathComponent("final.mp4"), outputVideoFormat: .mp4, titleSlug: "Shoot",
            cameraAngleFiles: [SourceTrackFile(role: "camera-2", url: directory.appendingPathComponent("camera-2.mov"))],
            cameraAngles: angles, programAudioRole: "camera-2"
        )
        try store.writeRecordingProject(for: take, settings: fixture.settings,
                                        sceneEvents: [.init(time: 0, scene: RecordingScene(settings: fixture.settings))],
                                        finalVideoURL: nil)
        let saved = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(saved.cameraAngles, angles)

        let merged = saved.keepingSavedMetadata(from: saved)
        XCTAssertEqual(merged.cameraAngles, angles, "an editor save merged with the saved file")
        XCTAssertEqual(merged.programAudioRole, "camera-2")

        let renamed = try store.renameProject(.init(projectURL: take.projectURL, title: "Podcast 1", settings: fixture.settings))
        XCTAssertEqual(renamed.cameraAngles, angles, "a rename")
        try store.recordCompletedExport(.init(projectURL: take.projectURL, record: .init(
            id: UUID(), createdAt: Date(), path: directory.appendingPathComponent("final.mp4").path, format: "mp4",
            resolution: "1080p", framesPerSecond: 30, quality: "high", fileSizeBytes: nil
        ), settings: fixture.settings))
        let exported = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(exported.cameraAngles, angles, "a finished export")
        XCTAssertEqual(exported.programAudioRole, "camera-2")
    }

    /// The app's own flow: drop the three files, open the project in the editor, edit it, and reopen it.
    @MainActor
    func testRealShootSurvivesTheEditor() async throws {
        guard let folder = ProcessInfo.processInfo.environment["BLITZRECORDER_MULTICAM_FIXTURE"] else {
            throw XCTSkip("BLITZRECORDER_MULTICAM_FIXTURE is not set")
        }
        let directory = URL(fileURLWithPath: folder)
        let fixture = try SyntheticRecording()
        let suite = "MulticamEditor.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingSettingsStore.save(fixture.settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.studioMode = .projects
        let urls = ["wide-shot.MOV", "plan-emmanuel.MP4", "plan-thomas.MOV"].map { directory.appendingPathComponent($0) }
        XCTAssertTrue(vm.importVideos(urls))
        await vm.libraryActions.videoImportTask?.value
        XCTAssertNil(vm.libraryActions.videoImportError)
        XCTAssertEqual(vm.studioMode, .edit, "one project opens in the editor")
        let project = try XCTUnwrap(vm.lastExportedProject)
        XCTAssertEqual(project.cameraAngles.map(\.role), ["camera", "camera-2", "camera-3"])
        let edits = try XCTUnwrap(EditorTimeRange.removing(.init(range: .init(start: 120, end: 121),
            edits: project.edits, takeDuration: 1_898)))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: edits, actionName: "Cut")))
        let projectURL = URL(fileURLWithPath: project.projectPath)
        try await settleSaves()
        let reopened = try TakeFileStore().loadRecordingProject(at: projectURL)
        XCTAssertEqual(reopened.edits, edits, "saved: \(vm.detailMessage)")
        XCTAssertEqual(vm.lastExportedProject?.edits, edits, "the editor still shows what was saved")
        XCTAssertEqual(reopened.cameraAngles, project.cameraAngles, "editing keeps the sync")
        XCTAssertEqual(reopened.programAudioRole, "camera-2")

        // Cut between cameras the way the number keys do: a new part at 10:00 on Thomas, side by side at 11:40,
        // then change the 10:00 part to Emmanuel.
        let shots = MulticamShot.shots(for: reopened.cameraAngles)
        XCTAssertTrue(vm.cutToCameraShot(.init(shot: shots[2], time: 600)))
        XCTAssertTrue(vm.cutToCameraShot(.init(shot: shots[3], time: 700)))
        XCTAssertTrue(vm.cutToCameraShot(.init(shot: shots[1], time: 600)))
        try await settleSaves()
        let cut = try TakeFileStore().loadRecordingProject(at: projectURL)
        let atTen = try XCTUnwrap(cut.sceneEvents.first { abs($0.time - 600) < 0.001 })
        XCTAssertEqual(atTen.scene.cameraFeed, "camera-2")
        XCTAssertNil(atTen.scene.sceneLayout.secondCameraFrame)
        let atEleven = try XCTUnwrap(cut.sceneEvents.first { abs($0.time - 700) < 0.001 })
        XCTAssertEqual(atEleven.scene.cameraFeed, "camera-2")
        XCTAssertEqual(atEleven.scene.secondCameraFeed, "camera-3")
        XCTAssertEqual(cut.sceneEvents.count, 4, "wide, side by side at 1:12, Emmanuel at 10:00, side by side at 11:40")
        XCTAssertEqual(cut.cameraAngles, project.cameraAngles)
    }

    /// Every queued editor save written, and each result handed back to the editor.
    @MainActor
    private func settleSaves() async throws {
        for _ in 0..<3 {
            ProjectSaveQueue.shared.waitUntilIdle()
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Set BLITZRECORDER_MULTICAM_FIXTURE to a folder with wide-shot.MOV, plan-emmanuel.MP4 (Osmo Pocket 4 on the
    /// left speaker) and plan-thomas.MOV (iPhone on the right speaker) to import a real three-camera shoot.
    func testRealShootBecomesOneSyncedSideBySideProject() async throws {
        guard let folder = ProcessInfo.processInfo.environment["BLITZRECORDER_MULTICAM_FIXTURE"] else {
            throw XCTSkip("BLITZRECORDER_MULTICAM_FIXTURE is not set")
        }
        let directory = URL(fileURLWithPath: folder)
        let fixture = try SyntheticRecording()
        let urls = ["plan-thomas.MOV", "wide-shot.MOV", "plan-emmanuel.MP4"].map { directory.appendingPathComponent($0) }
        let result = try await MulticamProjectImporter().importShoot(.init(urls: urls, settings: fixture.settings,
                                                                          onProgress: { _ in }))
        XCTAssertEqual(result.unmatched, [])
        let project = try XCTUnwrap(result.project)
        let angles = project.cameraAngles
        for angle in angles {
            print("angle", angle.role, angle.title, angle.offsetSeconds, angle.syncStatusText, angle.faceCount,
                  angle.face.map { "\($0)" } ?? "-")
        }
        let path = { (role: String) in project.sources.first { $0.role == role }.map { URL(fileURLWithPath: $0.path).lastPathComponent } }
        XCTAssertEqual(path("camera"), "wide-shot.MOV")
        XCTAssertEqual(path("camera-2"), "plan-emmanuel.MP4", "Emmanuel sits on the left")
        XCTAssertEqual(path("camera-3"), "plan-thomas.MOV")
        XCTAssertEqual(angles.record(role: "camera-2")?.offsetSeconds ?? 0, 18.07, accuracy: 0.034)
        XCTAssertEqual(angles.record(role: "camera-3")?.offsetSeconds ?? 0, 72.37, accuracy: 0.034)
        XCTAssertEqual(project.programAudioRole, "camera-2", "the Osmo's close mic is the program audio")
        XCTAssertEqual(project.sourceTimelineOffsetSeconds[CaptureSource.microphone.rawValue] ?? 0, 18.07, accuracy: 0.034)
        XCTAssertEqual(project.sceneEvents.count, 2, "the wide shot until both speakers' cameras roll")
        XCTAssertNil(project.sceneEvents[0].scene.cameraFeed)
        XCTAssertEqual(project.sceneEvents[1].time, 72.37, accuracy: 0.05)
        let scene = project.sceneEvents[1].scene
        XCTAssertEqual(scene.cameraFeed, "camera-2")
        XCTAssertEqual(scene.secondCameraFeed, "camera-3")

        let store = TakeFileStore()
        let projectURL = URL(fileURLWithPath: project.projectPath)
        _ = try store.updateProjectScene(at: projectURL, eventIndex: 1, baseSettings: fixture.settings) { $0.canvasPadding = 0.03 }
        let reloaded = try store.loadRecordingProject(at: projectURL)
        XCTAssertEqual(reloaded.cameraAngles, angles, "an editor save keeps the angles where the sync put them")
        XCTAssertEqual(reloaded.programAudioRole, "camera-2")

        // Three seconds of the side-by-side, exported: each speaker's face sits in their own half, the same size,
        // near the eye line the framing aimed for.
        let settings = store.recordingSettings(from: reloaded, baseSettings: fixture.settings, outputFormat: .mp4)
        let take = store.recordingTake(from: reloaded, settings: settings, outputFormat: .mp4)
        // The editor loads every angle into both camera slots, so a layout change can show any of them at once.
        let playback = try await Merger.editorPlaybackComposition(take: take, settings: settings,
            sceneEvents: store.sceneEvents(from: reloaded), cuts: [])
        XCTAssertEqual(playback.duration.seconds, 1_898.6, accuracy: 0.5)
        var edits = TimelineEdits.empty
        edits.cuts = [TimelineCut(start: 0, end: 300, kind: .manual, source: .user),
                      TimelineCut(start: 303, end: 1_900, kind: .manual, source: .user)]
        let output = fixture.root.appendingPathComponent("side-by-side.mp4")
        let exported = try await Merger.exportFinalVideo(.init(take: take, settings: settings,
            sceneEvents: store.sceneEvents(from: reloaded), backgroundMusic: nil, destinationURL: output,
            progressHandler: nil, timelineEdits: edits))
        let asset = AVURLAsset(url: exported)
        let exportedDuration = try await asset.load(.duration).seconds
        let exportedAudio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(exportedDuration, 3, accuracy: 0.1)
        XCTAssertEqual(exportedAudio.count, 1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let frame = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)).image
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: frame).perform([request])
        let faces = (request.results ?? []).map(\.boundingBox).filter { $0.height > 0.08 }.sorted { $0.midX < $1.midX }
        print("exported faces", faces)
        XCTAssertEqual(faces.count, 2)
        guard faces.count == 2 else { return }
        XCTAssertLessThan(faces[0].maxX, 0.5)
        XCTAssertGreaterThan(faces[1].minX, 0.5)
        XCTAssertEqual(faces[0].height, faces[1].height, accuracy: 0.04, "both speakers at the same size")
        for face in faces {
            XCTAssertEqual(1 - face.midY, MulticamShot.speakerEyeLine, accuracy: 0.1, "face centre from the top")
        }
    }
}
