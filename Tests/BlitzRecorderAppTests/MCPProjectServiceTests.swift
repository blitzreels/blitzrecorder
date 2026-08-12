import XCTest
@testable import BlitzRecorderApp

@MainActor
final class MCPProjectServiceTests: XCTestCase {
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
                quality: ExportVideoQuality.maximum.rawValue
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
        let access = AccessController(defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: access, defaults: defaults)
        coordinator.setOutputDirectory(outputDirectory)
        return Fixture(
            service: MCPProjectService(coordinator: coordinator),
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
