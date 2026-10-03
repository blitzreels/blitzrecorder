import AVFoundation
import AppKit
import MCP
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class MCPProjectServiceTests: XCTestCase {
    func testFrameReturnsImageAtTranscriptTimeWithCaptureOffsets() async throws {
        let fixture = try makeFixture(editorState: .empty)
        let source = try XCTUnwrap(fixture.project.sources.first(where: { $0.role == "screen" }))
        let writer = try VideoFileWriter(
            url: URL(fileURLWithPath: source.path), width: 640, height: 320,
            bitrate: 1_000_000, fps: 30, outputFormat: .mov
        )
        let generator = try CameraBlackFrameGenerator(.init(
            width: 640, height: 320,
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, framesPerSecond: 30
        ))
        for frame in 0..<60 {
            writer.append(try XCTUnwrap(generator.sampleBuffer(at: CMTime(value: Int64(frame), timescale: 30))))
            try await Task.sleep(for: .milliseconds(5))
        }
        _ = try await writer.finish()
        let url = URL(fileURLWithPath: fixture.project.projectPath)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        saved["timelineTrimOffsetSeconds"] = 1
        saved["sourceTimelineOffsetSeconds"] = ["screen": 0.25]
        try JSONSerialization.data(withJSONObject: saved).write(to: url)

        let frame = try await fixture.service.frame(.init(
            projectID: fixture.project.id, source: .screen, timeSeconds: 0.5
        ))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: frame.jpeg))
        XCTAssertEqual(decoded.pixelsWide, 640)
        XCTAssertEqual(decoded.pixelsHigh, 320)
        XCTAssertEqual(frame.metadata.projectID, fixture.project.id)
        XCTAssertEqual(frame.metadata.actualTimeSeconds, 0.5, accuracy: 1.0 / 30)
        XCTAssertEqual(frame.metadata.sourceTimelineEndSeconds, 1.25, accuracy: 1.0 / 30)

        let server = BlitzRecorderMCPServer(coordinator: fixture.coordinator)
        let body = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"project_frame","arguments":{"projectId":"\#(fixture.project.id.uuidString)","source":"screen","timeSeconds":0.5}}}"#
        let response = await server.respond(to: HTTPRequest(method: "POST", headers: [
            "Content-Type": "application/json", "Accept": "application/json",
            "Origin": "http://localhost:\(BlitzRecorderMCPServer.port)",
            "MCP-Protocol-Version": "2025-06-18"
        ], body: Data(body.utf8), path: BlitzRecorderMCPServer.endpoint))
        let responseData = try XCTUnwrap(response.bodyData)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let contents = try XCTUnwrap(result["content"] as? [[String: Any]])
        let image = try XCTUnwrap(contents.first { $0["type"] as? String == "image" })
        XCTAssertEqual(image["mimeType"] as? String, "image/jpeg")
        let base64 = try XCTUnwrap(image["data"] as? String)
        XCTAssertNotNil(Data(base64Encoded: base64).flatMap(NSBitmapImageRep.init(data:)))

        do {
            _ = try await fixture.service.frame(.init(projectID: fixture.project.id, source: .screen, timeSeconds: 10))
            XCTFail("Out-of-range frames must fail instead of returning a different moment.")
        } catch MCPProjectFrameError.outsideSource {}
    }

    func testFrameReportsMissingVideoAndRejectsInvalidTime() async throws {
        let fixture = try makeFixture(editorState: .empty)
        do {
            _ = try await fixture.service.frame(.init(projectID: fixture.project.id, source: .screen, timeSeconds: 0))
            XCTFail("Missing footage must return an error.")
        } catch MCPProjectFrameError.missingSource(let role) {
            XCTAssertEqual(role, "screen")
        }
        for time in [-1, Double.infinity, Double.nan] {
            do {
                _ = try await fixture.service.frame(.init(projectID: fixture.project.id, source: .screen, timeSeconds: time))
                XCTFail("Invalid timestamps must fail.")
            } catch MCPProjectFrameError.invalidTime {}
        }
    }

    func testExportAsIsUsesMP4AndSavedEditorRecipe() throws {
        let fixture = try makeFixture(editorState: .init(
            hiddenVideoSources: [SceneLayerKind.camera.rawValue],
            mutedAudioSources: [CaptureSource.microphone.rawValue],
            backgroundMusicPath: nil,
            backgroundMusicBookmarkData: nil,
            backgroundMusicVolume: nil,
            exportRecipe: .init(
                preset: ExportPerformancePreset.custom.rawValue,
                format: OutputVideoFormat.mov.rawValue,
                resolution: OutputResolution.p720.rawValue,
                framesPerSecond: 24,
                quality: ExportVideoQuality.maximum.rawValue,
                playbackRate: 1.2
            )
        ))

        let request = try fixture.service.makeExportRequest(.init(
            project: fixture.project,
            outputDirectory: fixture.outputDirectory
        ))

        XCTAssertEqual(request.outputFormat, .mp4)
        XCTAssertEqual(request.performanceProfile.resolution, .p720)
        XCTAssertEqual(request.performanceProfile.framesPerSecond, 24)
        XCTAssertEqual(request.performanceProfile.videoQuality, .maximum)
        XCTAssertEqual(request.hiddenVideoSources, [.camera])
        XCTAssertEqual(request.mutedAudioSources, [.microphone])
        XCTAssertEqual(request.destinationURL.pathExtension, "mp4")
        XCTAssertEqual(request.destinationURL.deletingLastPathComponent(), fixture.outputDirectory)
        XCTAssertEqual(request.playbackRate, 1.2, accuracy: 0.0001)
    }

    func testExportAsIsUsesSourceQualityWhenNoRecipeExists() throws {
        let fixture = try makeFixture(editorState: .empty)

        let request = try fixture.service.makeExportRequest(.init(
            project: fixture.project,
            outputDirectory: fixture.outputDirectory
        ))

        XCTAssertEqual(request.performanceProfile.preset, .custom)
        XCTAssertEqual(request.performanceProfile.resolution, .p1440)
        XCTAssertEqual(request.performanceProfile.framesPerSecond, 60)
        XCTAssertEqual(request.performanceProfile.videoQuality, .high)
    }

    func testOutputDirectoryDefaultsToConfiguredFolderAndAllowsSubfolder() throws {
        let fixture = try makeFixture(editorState: .empty)

        XCTAssertEqual(
            try fixture.service.resolveOutputDirectory(nil),
            fixture.outputDirectory.resolvingSymlinksInPath()
        )

        let requestedDirectory = fixture.outputDirectory.appendingPathComponent("shorts", isDirectory: true)
        XCTAssertEqual(
            try fixture.service.resolveOutputDirectory(requestedDirectory).path,
            requestedDirectory.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestedDirectory.path))
    }

    func testOutputDirectoryRejectsFolderOutsideConfiguredRoot() throws {
        let fixture = try makeFixture(editorState: .empty)
        let unauthorizedDirectory = temporaryDirectory()

        XCTAssertThrowsError(try fixture.service.resolveOutputDirectory(unauthorizedDirectory)) { error in
            guard case MCPProjectServiceError.outputDirectoryNotAuthorized = error else {
                return XCTFail("Expected outputDirectoryNotAuthorized, received \(error).")
            }
        }
    }

    func testProjectListAndTranscriptUseSavedProjectArtifacts() throws {
        let fixture = try makeFixture(editorState: .empty)
        let transcript = RecordingTranscript(
            version: 1,
            id: UUID(),
            mediaPath: fixture.project.projectPath,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 12,
            confidence: 0.9,
            text: "First line. Second line.",
            suggestedTitle: nil,
            speakers: [.init(id: "speaker-1", name: "Virgile", context: "")],
            segments: [
                .init(
                    id: UUID(),
                    speakerID: "speaker-1",
                    startTime: 0,
                    endTime: 12,
                    text: "First line. Second line.",
                    confidence: 0.9
                )
            ]
        )
        let transcriptStore = TranscriptArtifactStore()
        try transcriptStore.save(.init(
            transcript: transcript,
            locations: transcriptStore.locations(for: fixture.project)
        ))

        let list = fixture.service.listProjects(.all)
        let response = try fixture.service.transcript(.init(projectID: fixture.project.id))
        let details = try fixture.service.projectDetails(projectID: fixture.project.id)

        XCTAssertEqual(list.projects.count, 1)
        XCTAssertEqual(list.totalMatched, 1)
        XCTAssertEqual(list.returned, 1)
        XCTAssertEqual(list.projects.first?.id, fixture.project.id)
        XCTAssertEqual(list.projects.first?.hasTranscript, true)
        XCTAssertEqual(details.id, fixture.project.id)
        XCTAssertEqual(details.hasTranscript, true)
        XCTAssertEqual(details.exportRecipe.resolution, OutputResolution.p1440.rawValue)
        XCTAssertEqual(details.exportRecipe.framesPerSecond, 60)
        XCTAssertEqual(response.projectID, fixture.project.id)
        XCTAssertEqual(response.wordCount, 4)
        XCTAssertTrue(response.transcript.contains("Virgile"))
        XCTAssertTrue(response.transcript.contains("First line"))
    }

    func testProjectListFiltersAndPaginatesNewestFirst() throws {
        let fixture = try makeFixture(editorState: .empty)
        let matchingQuery = String(fixture.project.displayTitle.prefix(8))

        let matching = fixture.service.listProjects(.init(
            query: matchingQuery,
            recordedAfter: fixture.project.createdAt.addingTimeInterval(-1),
            recordedBefore: fixture.project.createdAt.addingTimeInterval(1),
            hasTranscript: false,
            limit: 1,
            offset: 0
        ))
        let skipped = fixture.service.listProjects(.init(
            query: matchingQuery,
            recordedAfter: nil,
            recordedBefore: nil,
            hasTranscript: nil,
            limit: 1,
            offset: 1
        ))

        XCTAssertEqual(matching.totalMatched, 1)
        XCTAssertEqual(matching.returned, 1)
        XCTAssertEqual(matching.projects.first?.id, fixture.project.id)
        XCTAssertEqual(skipped.totalMatched, 1)
        XCTAssertEqual(skipped.returned, 0)
        XCTAssertEqual(skipped.offset, 1)
    }

    func testProjectReadinessIgnoresOptionalTranscriptTextFile() throws {
        let fixture = try makeFixture(editorState: .empty)
        for source in fixture.project.sources where source.role != "transcript" {
            try Data().write(to: URL(fileURLWithPath: source.path))
        }

        let list = fixture.service.listProjects(.all)
        let details = try fixture.service.projectDetails(projectID: fixture.project.id)

        XCTAssertEqual(list.projects.first?.canExport, true)
        XCTAssertEqual(list.projects.first?.missingCaptureSourceRoles, [])
        XCTAssertEqual(details.canExport, true)
        XCTAssertEqual(details.missingCaptureSourceRoles, [])
        XCTAssertEqual(details.hasTranscript, false)
    }

    private struct Fixture {
        let service: MCPProjectService
        let coordinator: RecorderCoordinator
        let project: RecordingProject
        let outputDirectory: URL
    }

    private func makeFixture(
        editorState: RecordingProject.EditorStateSnapshot
    ) throws -> Fixture {
        let outputDirectory = temporaryDirectory()
        var settings = RecordingSettings()
        settings.outputDirectory = outputDirectory
        settings.outputResolution = .p1440
        settings.framesPerSecond = 60

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try store.writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: [
                RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))
            ],
            finalVideoURL: nil,
            editorState: editorState
        )
        let project = try store.loadRecordingProject(at: take.projectURL)

        let defaults = temporaryDefaults()
        RecordingSettingsStore.save(settings, defaults: defaults)
        let access = AccessController(defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        coordinator.setOutputDirectory(outputDirectory)
        return Fixture(
            service: MCPProjectService(coordinator: coordinator),
            coordinator: coordinator,
            project: project,
            outputDirectory: outputDirectory
        )
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "dev.blitzreels.blitzrecorder.mcp-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlitzRecorderMCPTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
