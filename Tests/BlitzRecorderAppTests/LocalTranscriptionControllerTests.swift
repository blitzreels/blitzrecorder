import Foundation
import XCTest
@testable import BlitzRecorderApp

final class LocalTranscriptionControllerTests: XCTestCase {
    @MainActor
    func testManualRequestDownloadsOnceAndTranscribesWhenAutomaticIsOff() async {
        let transcriptionStarted = expectation(description: "Transcription started")
        let engine = LocalTranscriptionEngineSpy(
            onTranscriptionStarted: { transcriptionStarted.fulfill() }
        )
        let suiteName = "LocalTranscriptionControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(false, forKey: "transcription.automatic.enabled")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let controller = LocalTranscriptionController(.init(
            engine: engine,
            modelStore: LocalTranscriptionModelStoreStub(),
            artifactStore: TranscriptArtifactStore(),
            fileStore: TakeFileStore(),
            defaults: defaults
        ))
        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        controller.retry(.recording(recordingURL))
        controller.downloadModels()

        await fulfillment(of: [transcriptionStarted], timeout: 2)

        let downloadCount = await engine.downloadCount
        let transcriptionCount = await engine.transcriptionCount
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(transcriptionCount, 1)
        XCTAssertTrue(controller.modelState.isReady)
        XCTAssertFalse(controller.isAutomaticEnabled)
    }

    @MainActor
    func testSelectedBackendLanguageAndSpeakerCountReachEngine() async {
        let transcriptionStarted = expectation(description: "Selected transcription started")
        let engine = LocalTranscriptionEngineSpy(
            onTranscriptionStarted: { transcriptionStarted.fulfill() }
        )
        let suiteName = "LocalTranscriptionControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(false, forKey: "transcription.automatic.enabled")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = LocalTranscriptionController(.init(
            engine: engine,
            modelStore: LocalTranscriptionModelStoreStub(),
            artifactStore: TranscriptArtifactStore(),
            fileStore: TakeFileStore(),
            defaults: defaults
        ))
        controller.selectedModel = .whisperMedium
        controller.selectedLanguage = .french
        controller.speakerCount = .two
        controller.retry(.recording(FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)))

        await fulfillment(of: [transcriptionStarted], timeout: 2)

        let downloadedModel = await engine.downloadedModel
        let transcribedRequest = await engine.transcribedRequest
        XCTAssertEqual(downloadedModel, .whisperMedium)
        XCTAssertEqual(transcribedRequest?.model, .whisperMedium)
        XCTAssertEqual(transcribedRequest?.language, .french)
        XCTAssertEqual(transcribedRequest?.speakerCount, .two)
        XCTAssertEqual(defaults.string(forKey: "transcription.speech.model"), "whisperMedium")
    }

}

private struct LocalTranscriptionModelStoreStub: LocalTranscriptionModelStoring {
    func isInstalled(_ model: TranscriptionSpeechModel) -> Bool { false }
    func installedSize(_ model: TranscriptionSpeechModel) -> Int64 { 1_024 }
}

private actor LocalTranscriptionEngineSpy: LocalTranscriptionEngineServing {
    private(set) var downloadCount = 0
    private(set) var transcriptionCount = 0
    private(set) var downloadedModel: TranscriptionSpeechModel?
    private(set) var transcribedRequest: LocalTranscriptionEngine.TranscribeRequest?
    private let onTranscriptionStarted: @Sendable () -> Void

    init(onTranscriptionStarted: @escaping @Sendable () -> Void) {
        self.onTranscriptionStarted = onTranscriptionStarted
    }

    func downloadModels(
        _ request: LocalTranscriptionEngine.DownloadRequest
    ) async throws {
        downloadCount += 1
        downloadedModel = request.model
        request.onUpdate(.init(fractionCompleted: 0.5, phase: "Downloading 1 of 2"))
        await Task.yield()
        request.onUpdate(.init(fractionCompleted: 1, phase: "Ready"))
    }

    func transcribe(
        _ request: LocalTranscriptionEngine.TranscribeRequest
    ) async throws -> RecordingTranscript {
        transcriptionCount += 1
        transcribedRequest = request
        onTranscriptionStarted()
        request.onUpdate(.init(stage: .preparingAudio))
        return RecordingTranscript(
            version: 1,
            id: UUID(),
            mediaPath: request.source.key,
            generatedAt: Date(),
            duration: 0,
            confidence: 1,
            text: "",
            suggestedTitle: nil,
            speakers: [],
            segments: []
        )
    }

    func removeModels(_ model: TranscriptionSpeechModel) async throws {}
}
