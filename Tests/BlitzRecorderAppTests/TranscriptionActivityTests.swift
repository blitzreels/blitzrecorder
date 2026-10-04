import Foundation
import XCTest
@testable import BlitzRecorderApp

final class TranscriptionActivityTests: XCTestCase {
    @MainActor
    func testProjectRefreshKeepsRetranscriptionActiveAndLateUpdatesCannotReopenFinishedJob() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "TranscriptionActivityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "transcription.automatic.enabled")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var settings = RecordingSettings()
        settings.outputDirectory = root
        settings.projectLibrary = .init(url: root, bookmarkData: nil)
        let fileStore = TakeFileStore()
        let take = try fileStore.createTake(settings: settings)
        let project = try fileStore.loadRecordingProject(at: take.projectURL)
        let transcript = RecordingTranscript(version: 1, id: UUID(), mediaPath: project.projectPath,
            generatedAt: Date(), duration: 1, confidence: 1, text: "Saved words", suggestedTitle: nil,
            speakers: [], segments: [])
        let artifacts = TranscriptArtifactStore()
        let locations = artifacts.locations(for: project)
        try artifacts.save(.init(transcript: transcript, locations: locations))
        let history = fileStore.loadProjectHistory(settings: settings).entries
        let entry = try XCTUnwrap(history.first)
        let started = expectation(description: "Transcription starts")
        started.expectedFulfillmentCount = 2
        let engine = ActivityTranscriptionEngine(.init(transcript: transcript, onStarted: { started.fulfill() }))
        let controller = LocalTranscriptionController(.init(engine: engine, modelStore: InstalledSpeechModelStore(),
            artifactStore: artifacts, fileStore: fileStore, defaults: defaults))
        await controller.syncProjects(history).value
        XCTAssertEqual(controller.status(for: entry), .ready(locations.jsonURL))
        controller.retry(.project(take.projectURL))
        try await waitFor { controller.status(for: entry) == .loadingModels }
        await controller.syncProjects(history).value
        XCTAssertEqual(controller.status(for: entry), .loadingModels)
        XCTAssertNotNil(controller.jobStartedAt[entry.projectPath])
        XCTAssertEqual(try artifacts.load(from: locations.jsonURL).text, "Saved words")
        await engine.finish()
        try await waitFor { controller.status(for: entry) == .ready(locations.jsonURL) }
        XCTAssertNil(controller.jobStartedAt[entry.projectPath])
        await engine.sendFirstJobUpdate()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.status(for: entry), .ready(locations.jsonURL))
        controller.retry(.project(take.projectURL))
        try await waitFor { controller.status(for: entry) == .loadingModels }
        await engine.sendFirstJobUpdate()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.status(for: entry), .loadingModels)
        await engine.finish()
        try await waitFor { controller.status(for: entry) == .ready(locations.jsonURL) }
        await fulfillment(of: [started], timeout: 2)
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Transcription status did not settle")
    }
}

private struct InstalledSpeechModelStore: LocalTranscriptionModelStoring {
    func isInstalled(_ model: TranscriptionSpeechModel) -> Bool { true }
    func installedSize(_ model: TranscriptionSpeechModel) -> Int64 { 1024 }
}

private actor ActivityTranscriptionEngine: LocalTranscriptionEngineServing {
    struct Configuration {
        let transcript: RecordingTranscript
        let onStarted: @Sendable () -> Void
    }
    let configuration: Configuration
    private var continuation: CheckedContinuation<Void, Never>?
    private var firstJobUpdate: (@Sendable (TranscriptionEngineUpdate) -> Void)?
    init(_ configuration: Configuration) { self.configuration = configuration }
    func downloadModels(_ request: LocalTranscriptionEngine.DownloadRequest) async throws {}
    func removeModels(_ model: TranscriptionSpeechModel) async throws {}
    func reassignSpeakers(_ request: LocalTranscriptionEngine.SpeakerFixRequest) async throws -> RecordingTranscript {
        request.onUpdate(.init(stage: .diarizing))
        return configuration.transcript
    }
    func transcribe(_ request: LocalTranscriptionEngine.TranscribeRequest) async throws -> RecordingTranscript {
        if firstJobUpdate == nil { firstJobUpdate = request.onUpdate }
        request.onUpdate(.init(stage: .loadingModels))
        configuration.onStarted()
        await withCheckedContinuation { continuation = $0 }
        return configuration.transcript
    }
    func finish() {
        continuation?.resume()
        continuation = nil
    }
    func sendFirstJobUpdate() { firstJobUpdate?(.init(stage: .preparingAudio)) }
}
